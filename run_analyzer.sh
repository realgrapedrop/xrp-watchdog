#!/bin/bash
cd /home/grapedrop/monitoring/xrp-watchdog
source venv/bin/activate
python analyzers/token_analyzer.py
