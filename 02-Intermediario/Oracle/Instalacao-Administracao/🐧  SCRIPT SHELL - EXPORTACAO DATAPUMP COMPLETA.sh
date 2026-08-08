export PATH=$PATH:/usr/local/bin
export PATH

. oraenv << EOF
CDB1
EOF

expdp system/system@XEPDB1 DIRECTORY=DUMP_DIR DUMPFILE=XEPDB1_03-10-2025.dmp LOGFILE=EXPORT_XEPDB1-03-10-2025.log full=y flashback_time=systimestamp
