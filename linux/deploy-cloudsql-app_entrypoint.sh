#!/bin/bash

export FLASK_APP=/vuln_cloudsql_app_target/app.py
export FLASK_DEBUG=0
flask run -h 0.0.0.0 -p 69