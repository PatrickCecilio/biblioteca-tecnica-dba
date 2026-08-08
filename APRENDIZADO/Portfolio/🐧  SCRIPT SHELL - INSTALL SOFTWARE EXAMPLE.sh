#!/usr/bin/env bash

# Exemplo derivado do procedimento documentado.
# Defina as variáveis com valores apropriados ao seu ambiente antes de executar.

export ORACLE_BASE="/u01/app/oracle"
export ORACLE_HOME="/u01/app/oracle/product/19c/dbhome_1"
export ORACLE_HOSTNAME="db-lab.example.com"
export INVENTORY_LOCATION="/u01/app/oraInventory"
export CV_ASSUME_DISTID="OEL7.6"
export PATH="${ORACLE_HOME}/bin:${PATH}"

"${ORACLE_HOME}/runInstaller" -silent \
  -waitforcompletion \
  -responseFile "${ORACLE_HOME}/install/response/db_install.rsp" \
  oracle.install.option=INSTALL_DB_SWONLY \
  ORACLE_HOSTNAME="${ORACLE_HOSTNAME}" \
  UNIX_GROUP_NAME=oinstall \
  INVENTORY_LOCATION="${INVENTORY_LOCATION}" \
  SELECTED_LANGUAGES=en \
  ORACLE_HOME="${ORACLE_HOME}" \
  ORACLE_BASE="${ORACLE_BASE}" \
  oracle.install.db.InstallEdition=EE \
  oracle.install.db.OSDBA_GROUP=dba \
  oracle.install.db.OSOPER_GROUP=dba \
  oracle.install.db.OSBACKUPDBA_GROUP=dba \
  oracle.install.db.OSDGDBA_GROUP=dba \
  oracle.install.db.OSKMDBA_GROUP=dba \
  oracle.install.db.OSRACDBA_GROUP=dba \
  SECURITY_UPDATES_VIA_MYORACLESUPPORT=false \
  DECLINE_SECURITY_UPDATES=true
