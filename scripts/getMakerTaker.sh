#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   getMakerTaker.sh <COUNT> [index <ledger_index> | hash <ledger_hash>]
#
# Output (TSV):
# ledger_index  close_time  tx_hash  tx_type  taker
# posted_gets   posted_pays
# exec_xrp  exec_iou_code  exec_iou_issuer  exec_iou  exec_price_xrp_per_iou
# counterparties

COUNT="${1:-1}"
START_MODE="${2:-}"
START_VAL="${3:-}"
CONTAINER="${RIPPLED_CONTAINER:-rippledvalidator}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd docker
require_cmd jq

get_latest_hash() {
  docker exec "$CONTAINER" rippled -q ledger closed | jq -r '.result.ledger_hash'
}
get_hash_from_index() {
  local idx="$1"
  docker exec "$CONTAINER" rippled -q json ledger "{\"ledger_index\":$idx}" | jq -r '.result.ledger_hash'
}

if [[ -z "$START_MODE" ]]; then
  CUR_HASH="$(get_latest_hash)"
elif [[ "$START_MODE" == "index" && -n "$START_VAL" ]]; then
  CUR_HASH="$(get_hash_from_index "$START_VAL")"
elif [[ "$START_MODE" == "hash" && -n "$START_VAL" ]]; then
  CUR_HASH="$START_VAL"
else
  echo "Usage: $0 <COUNT> [index <ledger_index> | hash <ledger_hash>]" >&2
  exit 1
fi

# Header
printf "ledger_index\tclose_time\ttx_hash\ttx_type\ttaker\tposted_gets\tposted_pays\texec_xrp\texec_iou_code\texec_iou_issuer\texec_iou\texec_price_xrp_per_iou\tcounterparties\n"

for ((i=0; i<COUNT; i++)); do
  LJSON="$(docker exec "$CONTAINER" rippled -q json ledger "{\"ledger_hash\":\"$CUR_HASH\",\"transactions\":true,\"expand\":true}")" || {
    echo "Failed to fetch ledger for hash $CUR_HASH" >&2
    exit 1
  }
  LEDGER_INDEX="$(printf '%s' "$LJSON" | jq -r '.result.ledger_index')"
  CLOSE_TIME="$(printf '%s' "$LJSON" | jq -r '.result.ledger.close_time_human // .result.ledger.close_time_iso')"
  PARENT_HASH="$(printf '%s' "$LJSON" | jq -r '.result.ledger.parent_hash')"

  JQ_FILTER=$(cat <<'JQ'
# Convert numbers safely
def num($x):
  if   $x == null then 0
  elif ($x|type) == "number" then $x
  elif ($x|type) == "string" then ($x|tonumber)
  elif ($x|type) == "object" and ($x|has("value")) then ($x.value|tonumber)
  else 0 end;

# Non-zero check
def nz($v; $eps): (($v|abs) > $eps);

.result.ledger.transactions[]
| . as $t
| .Account as $taker
| .TransactionType as $tt
|
# COUNTERPARTIES: owners of Modified/Deleted Offers where Account != taker
((($t.meta // $t.metaData).AffectedNodes // [])
  | map(.ModifiedNode? // .DeletedNode? // empty)
  | map(select(.LedgerEntryType=="Offer"))
  | map((.FinalFields?.Account // .PreviousFields?.Account // .NewFields?.Account))
  | map(select(. != null and . != $taker))
  | unique) as $makers
|
# Keep only txs with real counterparties
select(($makers | length) > 0)
|
# POSTED LEGS
def leg($x):
  if ($x|type)=="string" then {kind:"XRP",code:"XRP_drops",issuer:null,value:$x}
  elif ($x|type)=="object" then {kind:"IOU",code:($x.currency),issuer:($x.issuer),value:($x.value)}
  else {kind:null,code:null,issuer:null,value:null} end;
(leg($t.TakerGets)) as $posted_gets
| (leg($t.TakerPays)) as $posted_pays
|
# EXECUTED XRP (balance changes + fee)
(
  (($t.meta // $t.metaData).AffectedNodes // [])
  | map(.ModifiedNode? // .DeletedNode? // .CreatedNode? // empty)
  | map(select(.LedgerEntryType=="AccountRoot"))
  | map(select((.FinalFields?.Account // .NewFields?.Account // .PreviousFields?.Account) == $taker))
  | map( (num(.FinalFields?.Balance)) - (num(.PreviousFields?.Balance)) )
  | add // 0
) as $xrp_delta_drops
| (num($t.Fee)) as $fee_drops
| ($xrp_delta_drops + $fee_drops) as $exec_xrp_drops
| (($exec_xrp_drops|tonumber)/1000000.0) as $exec_xrp
|
# IOU deltas from RippleState
(
  (($t.meta // $t.metaData).AffectedNodes // [])
  | map(.ModifiedNode? // .DeletedNode? // empty)
  | map(select(.LedgerEntryType=="RippleState"))
  | map(
      . as $n
      | ($n.FinalFields // {}) as $F
      | ($n.PreviousFields // {}) as $P
      | ($F.Balance // $P.Balance // null) as $cur
      | ($F.HighLimit // $P.HighLimit // {}) as $H
      | ($F.LowLimit  // $P.LowLimit  // {}) as $L
      | if $cur == null then empty else
          ( num($F.Balance) - num($P.Balance) ) as $raw
          |
          if $H.issuer == $taker then
            {code: ($cur.currency // ""), issuer: ($cur.issuer // ""), amount: $raw}
          elif $L.issuer == $taker then
            {code: ($cur.currency // ""), issuer: ($cur.issuer // ""), amount: (-$raw)}
          else empty end
        end
    )
) as $iou_deltas
|
# Aggregate IOUs
( $iou_deltas
  | group_by(.code + "|" + .issuer)
  | map({code: (.[0].code), issuer: (.[0].issuer), amount: (map(.amount) | add)})
) as $iou_aggr
|
# Single IOU for pricing
(
  if ($iou_aggr|length)==1 then
    $iou_aggr[0]
  else
    null
  end
) as $one_iou
|
# Executed price
(
  if ($one_iou != null) then
    ( ($exec_xrp|tonumber)|abs )    as $xrp_abs
    | ( ($one_iou.amount|tonumber)|abs ) as $iou_abs
    | if nz($xrp_abs; 0.0) and nz($iou_abs; 0.0) then
        ($xrp_abs / $iou_abs)
      else
        null
      end
  else
    null
  end
) as $price_xrp_per_iou
|
# Format posted legs
($posted_gets.kind + ":" + ($posted_gets.code // "null") + (if $posted_gets.issuer then "/" + $posted_gets.issuer else "" end) + "=" + ($posted_gets.value // "null")) as $posted_gets_str
| ($posted_pays.kind + ":" + ($posted_pays.code // "null") + (if $posted_pays.issuer then "/" + $posted_pays.issuer else "" end) + "=" + ($posted_pays.value // "null")) as $posted_pays_str
|
[
  $li,
  $ct,
  (.hash // ""),
  ($tt // ""),
  ($taker // ""),
  $posted_gets_str,
  $posted_pays_str,
  ($exec_xrp|tostring),
  ($one_iou.code // ""),
  ($one_iou.issuer // ""),
  (if $one_iou then (($one_iou.amount|tonumber)|abs|tostring) else "" end),
  (if $price_xrp_per_iou then ($price_xrp_per_iou|tostring) else "" end),
  ($makers | join(","))
] | @tsv
JQ
)

  printf '%s' "$LJSON" | jq -r --arg li "$LEDGER_INDEX" --arg ct "$CLOSE_TIME" "$JQ_FILTER"

  CUR_HASH="$PARENT_HASH"
done
