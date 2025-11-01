#!/bin/bash
cd /home/grapedrop/monitoring/xrp-watchdog
source venv/bin/activate
python collectors/collection_orchestrator.py 130 --analyze
