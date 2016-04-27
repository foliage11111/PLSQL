REM $Id: analyze.sql,v 200.1 2014/05/14 20:45:59 alayton Exp $
REM +=========================================================================+
REM |                 Copyright (c) 2001 Oracle Corporation                   |
REM |                    Redwood Shores, California, USA                      |
REM |                         All rights reserved.                            |
REM +=========================================================================+
REM |                                                                         |
REM | FILENAME                                                                |
REM |    analyze_all.sql                                                      | 
REM |                                                                         |
REM | DESCRIPTION                                                             |
REM |    Wrapper SQL to submit the po_apprvl_analyzer_pkg.main procedure      |
REM |                                                                         |
REM | HISTORY                                                                 |
REM | 01-FEB-2013 ALUMPE  Created.                                            |
REM | 23-DEC-2014 ALAYTON Renamed and hanged to ALL mode                      |   
REM +=========================================================================+

REM ANALYZER_BUNDLE_START 
REM 
REM COMPAT: 12.0 12.1 12.2 
REM 
REM MENU_TITLE: Approval Analyzer Diagnostic Script (All) 
REM
REM MENU_START
REM SQL: Run PO Approval Analyzer in "all" Mode 
REM FNDLOAD: Load PO Approval Analyzer as a Concurrent Program 
REM MENU_END 
REM 
REM HELP_START  
REM 
REM  R12: Approval Analyzer Diagnostic Script Help [Doc ID: 1525670.1]
REM
REM  Compatible: 12.0|12.1|12.2
REM
REM  Explanation of available options:
REM
REM    (1) Runs PO Approval Analyzer as APPS in "all" mode
REM        o Runs analyze_all.sql (sql wrapper for ap_gdf_detect_pkg.main)
REM        o Creates an HTML report file: 
REM          MENU/output/PO-APPRVL-ANLZ-<timestamp>.html 
REM        o Creates a log: PO-APPRVL-ANLZ-<timestamp>.log
REM
REM    (2) Runs FNDLOAD to Install PO Approval Analyzer as a 
REM         Concurrent Program
REM        o Concurrent Program Name: "PODIAGAA"
REM        o Default Request Group: "All Reports" (PO Application) 
REM 
REM HELP_END 
REM 
REM FNDLOAD_START 
REM PROD_TOP: PO_TOP
REM DEF_REQ_GROUP: All Reports
REM PROG_NAME: PODIAGAA 
REM PROG_TEMPLATE: podiagaa_prog.ldt
REM PROD_SHORT_NAME: PO 
REM
REM FNDLOAD_END 
REM
REM DEPENDENCIES_START 
REM
REM po_approval_analyzer.sql
REM
REM DEPENDENCIES_END
REM  
REM RUN_OPTS_START
REM
REM RUN_OPTS_END 
REM
REM OUTPUT_TYPE: UTL_FILE
REM
REM ANALYZER_BUNDLE_END 

SET SERVEROUTPUT ON SIZE 1000000
SET ECHO OFF 
SET VERIFY OFF
SET DEFINE "&"

PROMPT
PROMPT Submitting PO Approval Analyzer.
PROMPT ===========================================================================
PROMPT Enter the org_id for the operating unit.  This parameter is required.
PROMPT ===========================================================================
PROMPT
ACCEPT ou NUMBER DEFAULT -1 -
       PROMPT 'Enter the org_id: '
PROMPT
PROMPT ===========================================================================
PROMPT Enter the date from which to begin validating transactions.
PROMPT ===========================================================================
PROMPT
ACCEPT from_date DATE FORMAT 'DD-MON-YYYY' PROMPT 'Enter the START DATE [DD-MON-YYYY]: '
PROMPT
PROMPT
PROMPT ===========================================================================
PROMPT Enter the maximum number of rows to display on row limited queries
PROMPT ===========================================================================
PROMPT
ACCEPT max_rows NUMBER DEFAULT 200 -
       PROMPT 'Enter the maximum rows to display [200]: '
PROMPT
PROMPT

DECLARE
  l_org_id     NUMBER := &ou;
  l_trx_type   VARCHAR2(15) := 'ANY';
  l_trx_num    VARCHAR2(20) := null;
  l_rel_num    NUMBER := null;
  l_from_date  DATE := to_date('&from_date'); 
  l_max_rows   NUMBER := &max_rows;

BEGIN

  IF l_org_id < 0 THEN
    l_org_id := null;
  END IF;

  IF l_max_rows < 0 THEN
    l_max_rows := 20;
  END IF;

  IF l_from_date is null THEN
    l_from_date := sysdate-90;
  END IF;

  po_apprvl_analyzer_pkg.main_all(
      p_org_id => l_org_id,
      p_from_date => l_from_date,
      p_max_output_rows => 20,
      p_debug_mode => 'Y');

EXCEPTION WHEN OTHERS THEN
  dbms_output.put_line('Error encountered: '||sqlerrm);
END;
/
exit;
