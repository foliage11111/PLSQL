SET DEFINE '~'
REM +=======================================================================+
REM |    Copyright (c) 2012 Oracle Corporation, Redwood Shores, CA, USA     |
REM |                         All rights reserved.                          |
REM +=======================================================================+
REM | Framework 3.0.27                                                      |
REM |                                                                       |
REM | FILENAME                                                              |
REM |   po_apprvl_analyzer_pkg.sql                                          |
REM |                                                                       |
REM | DESCRIPTION                                                           |
REM |   Script automating knowledge for on-site analysis of PO workflow     |
REM |   approval errors and other PO recurring issues.                      |
REM |                                                                       |
REM | HISTORY                                                               |
REM |  18-JAN-2013 PFIORENT                                                 | 
REM |              & ALUMPE Draft version created                           |
REM |  15-MAR-2013 ALUMPE   Added approval hierarchy validations            |
REM |  16-JUL-2013 ALUMPE   Added errors to output on parameter validation  |
REM |  14-MAY-2014 ALAYTON  Added Note 1304639.1, case #1                   |
REM |  15-DEC-2014 CGASPAR  Added code level check from 222339.1  v.120.19  | 
REM |  30-DEC-2014 ALAYTON  Changes to support SINGLE/ALL modes             |
REM |  10-FEB-2015 CGASPAR  Multiples changes and new signatures            |
REM |  02-APR-2015 ALAYTON  Automated Troubleshooting related changes       |
REM |  05-OCT-2015 CGASPAR  New signatures and added functionality          |
REM +=======================================================================+

WHENEVER SQLERROR EXIT

declare

apps_version FND_PRODUCT_GROUPS.RELEASE_NAME%TYPE;
	
BEGIN
 SELECT max(release_name) INTO apps_version
 FROM fnd_product_groups;

 apps_version := substr(apps_version,1,2);
    
-- Validation to verify analyzer is run on proper e-Business application version
-- So will fail before package is created
 if apps_version < '12' then 
	dbms_output.put_line('***************************************************************');
    dbms_output.put_line('*** WARNING WARNING WARNING WARNING WARNING WARNING WARNING ***');
    dbms_output.put_line('***************************************************************');
    dbms_output.put_line('*** This instance is eBusiness Suite version '|| apps_version ||'             ***');
    dbms_output.put_line('*** This Analyzer script must run in version 12 or above    ***');
    dbms_output.put_line('*** Note: the error below is intentional                    ***');
    raise_application_error(-20001, 'ERROR: The script requires eBusiness Version 12 or higher');
 end if;

END;
/

-- PSD #1
CREATE OR REPLACE PACKAGE po_apprvl_analyzer_pkg AUTHID CURRENT_USER AS


TYPE section_rec IS RECORD(
  name           VARCHAR2(255),
  result         VARCHAR2(1), -- E,W,S
  error_count    NUMBER,
  warn_count     NUMBER,
  success_count  NUMBER,
  print_count    NUMBER);

TYPE rep_section_tbl IS TABLE OF section_rec INDEX BY BINARY_INTEGER;
TYPE hash_tbl_2k     IS TABLE OF VARCHAR2(2000) INDEX BY VARCHAR2(255);
TYPE hash_tbl_4k     IS TABLE OF VARCHAR2(4000) INDEX BY VARCHAR2(255);
TYPE hash_tbl_8k     IS TABLE OF VARCHAR2(8000) INDEX BY VARCHAR2(255);
TYPE hash_tbl_num    IS TABLE OF NUMBER INDEX BY VARCHAR2(255);
TYPE col_list_tbl    IS TABLE OF DBMS_SQL.VARCHAR2_TABLE;
TYPE varchar_tbl     IS TABLE OF VARCHAR2(255);

TYPE signature_rec IS RECORD(
  sig_sql          VARCHAR2(32000),
  title            VARCHAR2(255),
  fail_condition   VARCHAR2(4000),
  problem_descr    VARCHAR2(4000),
  solution         VARCHAR2(4000),
  success_msg      VARCHAR2(4000),
  print_condition  VARCHAR2(8),
  fail_type        VARCHAR2(1),
  print_sql_output VARCHAR2(2),
  limit_rows       VARCHAR2(1),
  extra_info       HASH_TBL_4K,
  child_sigs       VARCHAR_TBL := VARCHAR_TBL(),
  include_in_xml   VARCHAR2(1));

TYPE signature_tbl IS TABLE OF signature_rec INDEX BY VARCHAR2(255);

PROCEDURE main (
      p_mode            IN VARCHAR2 DEFAULT null,
      p_org_id          IN NUMBER   DEFAULT null,
      p_trx_type        IN VARCHAR2 DEFAULT null,
      p_trx_num         IN VARCHAR2 DEFAULT null,
      p_release_num     IN NUMBER   DEFAULT null,
      p_include_wf      IN VARCHAR2 :='Y',
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y',
      p_calling_from    IN VARCHAR2 DEFAULT null);


PROCEDURE main_single(
      p_org_id          IN NUMBER   DEFAULT null,
      p_trx_type        IN VARCHAR2 DEFAULT null,
      p_trx_num         IN VARCHAR2 DEFAULT null,
      p_release_num     IN NUMBER   DEFAULT null,
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y');


PROCEDURE main_all(
      p_org_id          IN NUMBER   DEFAULT null,
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y');          

PROCEDURE main_cp ( 
      errbuf            OUT VARCHAR2, 
      retcode           OUT VARCHAR2,
      p_mode            IN VARCHAR2,  
      p_org_id          IN NUMBER,    
      p_dummy1          IN VARCHAR2,  
      p_trx_type        IN VARCHAR2,  
      p_dummy2          IN VARCHAR2,  
      p_po_num          IN VARCHAR2,  
      p_dummy3          IN VARCHAR2,  
      p_release_num     IN NUMBER,    
      p_dummy4          IN VARCHAR2,  
      p_req_num         IN VARCHAR2,  
      p_from_date       IN VARCHAR2,  
      p_max_output_rows IN NUMBER,    
      p_debug_mode      IN VARCHAR2); 

FUNCTION get_result   RETURN VARCHAR2;
FUNCTION get_fail_msg RETURN VARCHAR2;
FUNCTION get_exc_msg  RETURN VARCHAR2;
FUNCTION get_doc_amts(p_amt_type IN VARCHAR2) RETURN NUMBER;
FUNCTION chk_pkg_body_version(p_package_name IN VARCHAR2, p_expected_version IN VARCHAR2) RETURN NUMBER; -- return 1 if higher, 0 if the same, -1 if lower

FUNCTION get_ame_rules_for_trxn(p_trxn_id IN VARCHAR2) RETURN VARCHAR2;
FUNCTION get_ame_approvers_for_trxn(p_trxn_id VARCHAR2) RETURN VARCHAR2;


--PO CUSTOM START
g_reset_node           DBMS_XMLDOM.DOMNode;
--PO CUSTOM END

END po_apprvl_analyzer_pkg;
/
show errors

CREATE OR REPLACE PACKAGE BODY po_apprvl_analyzer_pkg AS
-- $Id: po_approval_analyzer.sql,v 200.7 2015/10/05 09:36:45 cgaspar Exp $

----------------------------------
-- Global Variables             --
----------------------------------
g_sect_no NUMBER := 1;
g_log_file         UTL_FILE.FILE_TYPE;
g_out_file         UTL_FILE.FILE_TYPE;
g_print_to_stdout  VARCHAR2(1) := 'N';
g_is_concurrent    BOOLEAN := (to_number(nvl(FND_GLOBAL.CONC_REQUEST_ID,0)) >  0);
g_debug_mode       VARCHAR2(1);
g_max_output_rows  NUMBER := 10;
g_family_result    VARCHAR2(1);


g_errbuf           VARCHAR2(1000);
g_retcode          VARCHAR2(1);

g_query_start_time TIMESTAMP;
g_query_elapsed    INTERVAL DAY(2) TO SECOND(3);
g_analyzer_start_time TIMESTAMP;
g_analyzer_elapsed    INTERVAL DAY(2) TO SECOND(3);

g_signatures      SIGNATURE_TBL;
g_sections        REP_SECTION_TBL;
g_section_toc	  VARCHAR2(32767);
g_section_sig     NUMBER;
sig_count         NUMBER;
g_sql_tokens      HASH_TBL_2K;
g_rep_info        HASH_TBL_2K;
g_parameters      HASH_TBL_2K;
g_exec_summary      HASH_TBL_2K;
g_item_id         INTEGER := 0;
g_sig_id          INTEGER := 0;
g_parent_sig_id   INTEGER := 0;
analyzer_title VARCHAR2(255);
g_mos_patch_url   VARCHAR2(255) :=
  'https://support.oracle.com/epmos/faces/ui/patch/PatchDetail.jspx?patchId=';
-- PSD #15  
g_mos_doc_url     VARCHAR2(255) :=
  'https://support.oracle.com/epmos/faces/DocumentDisplay?parent=ANALYZER&sourceId=1525670.1&id=';
g_hidden_xml      XMLDOM.DOMDocument;


g_app_method      VARCHAR2(15);
g_curr_empid      NUMBER;
g_app_results     HASH_TBL_2K;
g_doc_amts        HASH_TBL_NUM;
g_use_ame         BOOLEAN := false;
g_parent_sig_count NUMBER;
g_preserve_trailing_blanks BOOLEAN := false;

----------------------------------------------------------------
-- Debug, log and output procedures                          --
----------------------------------------------------------------

PROCEDURE enable_debug IS
BEGIN
  g_debug_mode := 'Y';
END enable_debug;

PROCEDURE disable_debug IS
BEGIN
  g_debug_mode := 'N';
END disable_debug;

PROCEDURE print_log(p_msg IN VARCHAR2) is
BEGIN
  IF NOT g_is_concurrent THEN
    utl_file.put_line(g_log_file, p_msg);
    utl_file.fflush(g_log_file);
  ELSE
    fnd_file.put_line(FND_FILE.LOG, p_msg);
  END IF;

  IF (g_print_to_stdout = 'Y') THEN
    dbms_output.put_line(substr(p_msg,1,254));
  END IF;
EXCEPTION WHEN OTHERS THEN
  dbms_output.put_line(substr('Error in print_log: '||sqlerrm,1,254));
  raise;
END print_log;

PROCEDURE debug(p_msg VARCHAR2) is
 l_time varchar2(25);
BEGIN
  IF (g_debug_mode = 'Y') THEN
    l_time := to_char(sysdate,'DD-MON-YY HH24:MI:SS');

    IF NOT g_is_concurrent THEN
      utl_file.put_line(g_log_file, l_time||'-'||p_msg);
    ELSE
      fnd_file.put_line(FND_FILE.LOG, l_time||'-'||p_msg);
    END IF;

    IF g_print_to_stdout = 'Y' THEN
      dbms_output.put_line(substr(l_time||'-'||p_msg,1,254));
    END IF;

  END IF;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in debug');
  raise;
END debug;


PROCEDURE print_out(p_msg IN VARCHAR2
                   ,p_newline IN VARCHAR  DEFAULT 'Y' ) is
BEGIN
  IF NOT g_is_concurrent THEN
    IF (p_newline = 'N') THEN
       utl_file.put(g_out_file, p_msg);
    ELSE
       utl_file.put_line(g_out_file, p_msg);
    END IF;
    utl_file.fflush(g_out_file);
  ELSE
     IF (p_newline = 'N') THEN
        fnd_file.put(FND_FILE.OUTPUT, p_msg);
     ELSE
        fnd_file.put_line(FND_FILE.OUTPUT, p_msg);
     END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in print_out');
  raise;
END print_out;


PROCEDURE print_error (p_msg VARCHAR2) is
BEGIN
  print_out('<div class="diverr">'||p_msg);
  print_out('</div>');
END print_error;



----------------------------------------------------------------
--- Time Management                                          ---
----------------------------------------------------------------

PROCEDURE get_current_time (p_time IN OUT TIMESTAMP) IS
BEGIN
  SELECT localtimestamp(3) INTO p_time
  FROM   dual;
END get_current_time;

FUNCTION stop_timer(p_start_time IN TIMESTAMP) RETURN INTERVAL DAY TO SECOND IS
  l_elapsed INTERVAL DAY(2) TO SECOND(3);
BEGIN
  SELECT localtimestamp - p_start_time  INTO l_elapsed
  FROM   dual;
  RETURN l_elapsed;
END stop_timer;

FUNCTION format_elapsed (p_elapsed IN INTERVAL DAY TO SECOND) RETURN VARCHAR2 IS
  l_days         VARCHAR2(3);
  l_hours        VARCHAR2(2);
  l_minutes      VARCHAR2(2);
  l_seconds      VARCHAR2(6);
  l_fmt_elapsed  VARCHAR2(80);
BEGIN
  l_days := EXTRACT(DAY FROM p_elapsed);
  IF to_number(l_days) > 0 THEN
    l_fmt_elapsed := l_days||' days';
  END IF;
  l_hours := EXTRACT(HOUR FROM p_elapsed);
  IF to_number(l_hours) > 0 THEN
    IF length(l_fmt_elapsed) > 0 THEN
      l_fmt_elapsed := l_fmt_elapsed||', ';
    END IF;
    l_fmt_elapsed := l_fmt_elapsed || l_hours||' Hrs';
  END IF;
  l_minutes := EXTRACT(MINUTE FROM p_elapsed);
  IF to_number(l_minutes) > 0 THEN
    IF length(l_fmt_elapsed) > 0 THEN
      l_fmt_elapsed := l_fmt_elapsed||', ';
    END IF;
    l_fmt_elapsed := l_fmt_elapsed || l_minutes||' Min';
  END IF;
  l_seconds := EXTRACT(SECOND FROM p_elapsed);
  IF length(l_fmt_elapsed) > 0 THEN
    l_fmt_elapsed := l_fmt_elapsed||', ';
  END IF;
  l_fmt_elapsed := l_fmt_elapsed || l_seconds||' Sec';
  RETURN(l_fmt_elapsed);
END format_elapsed;


----------------------------------------------------------------
--- File Management                                          ---
----------------------------------------------------------------

PROCEDURE initialize_files is
  l_date_char        VARCHAR2(20);
  l_log_file         VARCHAR2(200);
  l_out_file         VARCHAR2(200);
  l_file_location    V$PARAMETER.VALUE%TYPE;
  l_instance         VARCHAR2(40);
  l_host         VARCHAR2(40);
  NO_UTL_DIR         EXCEPTION;
  
BEGIN
get_current_time(g_analyzer_start_time);

  IF NOT g_is_concurrent THEN

    SELECT to_char(sysdate,'YYYY-MM-DD_hh_mi') INTO l_date_char from dual;
	
	SELECT instance_name, host_name
    INTO l_instance, l_host
    FROM v$instance;

    l_log_file := 'PO-APPRVL-ANLZ-'||l_date_char||'.log';
    l_out_file := 'PO-APPRVL-ANLZ-'||l_date_char||'.html';

    
    SELECT decode(instr(value,','),0,value,
           SUBSTR (value,1,instr(value,',') - 1))
    INTO   l_file_location
    FROM   v$parameter
    WHERE  name = 'utl_file_dir';

	-- Set maximum line size to 10000 for encoding of base64 icon
    IF l_file_location IS NULL THEN
      RAISE NO_UTL_DIR;
    ELSE
      g_out_file := utl_file.fopen(l_file_location, l_out_file, 'w',10000);
      g_log_file := utl_file.fopen(l_file_location, l_log_file, 'w',10000);
    END IF;

    dbms_output.put_line('Output Files are located on Host : '||l_host);
    dbms_output.put_line('Output file : '||l_file_location||'/'||l_out_file);
    dbms_output.put_line('Log file:     '||l_file_location||'/'||l_log_file);
  END IF;
EXCEPTION
  WHEN NO_UTL_DIR THEN
    dbms_output.put_line('Exception: Unable to identify a valid output '||
      'directory for UTL_FILE in initialize_files');
    raise;
  WHEN OTHERS THEN
    dbms_output.put_line('Exception: '||sqlerrm||' in initialize_files');
    raise;
END initialize_files;


PROCEDURE close_files IS
BEGIN
  debug('Entered close_files');
  print_out('</BODY></HTML>');
  IF NOT g_is_concurrent THEN
    debug('Closing files');
    utl_file.fclose(g_log_file);
    utl_file.fclose(g_out_file);
  END IF;
END close_files;


----------------------------------------------------------------
-- REPORTING PROCEDURES                                       --
----------------------------------------------------------------

----------------------------------------------------------------
-- Prints HTML page header and auxiliary Javascript functions --
-- Notes:                                                     --
-- Looknfeel styles for the o/p must be changed here          --
----------------------------------------------------------------

PROCEDURE print_page_header is
BEGIN
  -- HTML header
  print_out('
<HTML><HEAD>
  <meta http-equiv="content-type" content="text/html; charset=ISO-8859-1">
  <meta http-equiv="X-UA-Compatible" content="IE=9">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">');

  -- Page Title
  print_out('<TITLE>Analyzer Report</TITLE>');

  -- Styles
  print_out('
<STYLE type="text/css">
body {
  background-color:#ffffff;
  font-family:Arial;
  font-size:12pt;
  margin-left: 30px;
  margin-right: 30px;
  margin-top: 25px;
  margin-bottom: 25px;
}
tr {
  font-family: Tahoma, Helvetica, Geneva, sans-serif;
  font-size: small;
  color: #3D3D3D;
  background-color: white;
  padding: 5px;
}
tr.top {
  vertical-align:top;
}
tr.master {
  padding-bottom: 20px;
  background-color: white;
}
th {
  font-family: inherit;
  font-size: inherit;
  font-weight: bold;
  text-align: left;
  background-color: #BED3E9;
  color: #3E3E3E;
  padding: 5px;
}
th.master {
  font-family: Arial, Helvetica, sans-serif;
  padding-top: 10px;
  font-size: inherit;
  background-color: #BED3E9;
  color: #35301A;
}
th.rep {
  white-space: nowrap;
  width: 5%;
}
td {
  padding: inherit;
  font-family: inherit;
  font-size: inherit;
  font-weight: inherit;
  color: inherit;
  background-color: inherit;
  text-indent: 0px;
}
td.hlt {
  padding: inherit;
  font-family: inherit;
  font-size: inherit;
  font-weight: bold;
  color: #333333;
  background-color: #FFE864;
  text-indent: 0px;
}

a {color: #0066CC;}
a:visited { color: #808080;}
a:hover { color: #0099CC;}
a:active { color: #0066CC;}

.detail {
  text-decoration:none;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
}
.detailsmall {
  text-decoration:none;
  font-size: xx-small;
}
.table1 {
   border: 1px solid #EAEAEA;
  vertical-align: middle;
  text-align: left;
  padding: 3px;
  margin: 1px;
  width: 100%;
  font-family: Arial, Helvetica, sans-serif;
  border-spacing: 1px;
  background-color: #F5F5F5;
}
.toctable {
  background-color: #F4F4F4;
}
.TitleBar {
font-family: Calibri;
background-color: #152B40;
padding: 9px;
margin: 0px;
box-shadow: 3px 3px 3px #AAAAAA;
color: #F4F4F4;
font-size: xx-large;
font-weight: bold;
overflow:hidden;
}
.TitleImg {
float: right;
vertical-align: top;
padding-top: -10px;
}

.Title1{
font-size: xx-large;
}

.Title2{
font-size: medium;
}
.divSection {
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
  font-family: Arial, Helvetica, sans-serif;
  background-color: #CCCCCC;
  border: 1px solid #DADADA;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
  overflow:hidden;
}
.divSectionTitle {
width: 98.5%;
font-family: Calibri;
font-weight: bold;
background-color: #152B40;
color: #FFFFFF;
padding: 9px;
margin: 0px;
box-shadow: 3px 3px 3px #AAAAAA;
-moz-border-radius: 6px;
-webkit-border-radius: 6px;
border-radius: 6px;
height: 30px;
overflow:hidden;
}
.columns       { 
width: 98.5%; 
font-family: Calibri;
font-weight: bold;
background-color: #254B72;
color: #FFFFFF;
padding: 9px;
margin: 0px;
box-shadow: 3px 3px 3px #AAAAAA;
-moz-border-radius: 6px;
-webkit-border-radius: 6px;
border-radius: 6px;
height: 30px;
}
div.divSectionTitle div   { height: 30px; float: left; }
div.left          { width: 75%; background-color: #152B40; font-size: x-large; border-radius: 6px; }
div.right         { width: 25%; background-color: #152B40; font-size: medium; border-radius: 6px;}
div.clear         { clear: both; }
<!--End BBURBAGE code for adding the logo into the header -->
.sectHideShow {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  background-color: #254B72;
  color: #1D70AD;
}

.sectHideShowLnk {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  background-color: #254B72;
  color: #1D70AD;
}
.divSubSection {
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
  font-family: Arial, Helvetica, sans-serif;
  background-color: #E4E4E4;
  border: 1px solid #DADADA;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
}
.divSubSectionTitle {
  font-family: Arial, Helvetica, sans-serif;
  font-size: large;
  font-weight: bold;
  background-color: #888888;
  color: #FFFFFF;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
}
.divItem {
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
  font-family: Arial, Helvetica, sans-serif;
  background-color: #F4F4F4;
  border: 1px solid #EAEAEA;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
}
.divItemTitle {
  font-family: Arial, Helvetica, sans-serif;
  font-size: medium;
  font-weight: bold;
  color: #336699;
  border-bottom-style: solid;
  border-bottom-width: medium;
  border-bottom-color: #3973AC;
  margin-bottom: 9px;
  padding-bottom: 2px;
  margin-left: 3px;
  margin-right: 3px;
}
.divwarn {
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
  font-family: Arial, Helvetica, sans-serif;
  color: #333333;
  background-color: #FFEF95;
  border: 0px solid #FDC400;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
  font-size: small;
}
.divwarn1 {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: #9B7500;
  margin-bottom: 9px;
  padding-bottom: 2px;
  margin-left: 3px;
  margin-right: 3px;
}
.diverr {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: white;
  background-color: #F04141;
  box-shadow: 3px 3px 3px #AAAAAA;
   -moz-border-radius: 6px;
   -webkit-border-radius: 6px;
  border-radius: 6px;
  margin: 3px;
}
.divuar {
  border: 0px solid #CC0000;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: normal;
  background-color: #FFD8D8;
  color: #333333;
  padding: 9px;
  margin: 3px;
  box-shadow: 3px 3px 3px #AAAAAA;
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
}
.divuar1 {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: #CC0000;
  margin-bottom: 9px;
  padding-bottom: 2px;
  margin-left: 3px;
  margin-right: 3px;
}
.divok {
  border: 1px none #00CC99;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: normal;
  background-color: #ECFFFF;
  color: #333333;
  padding: 9px;
  margin: 3px;
  box-shadow: 3px 3px 3px #AAAAAA;
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
}
.divok1 {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: #006600;
  margin-bottom: 9px;
  padding-bottom: 2px;
  margin-left: 3px;
  margin-right: 3px;
}
.divsol {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  background-color: #D9E6F2;
  color: #333333;
  padding: 9px;
  margin: 0px;
  box-shadow: 3px 3px 3px #AAAAAA;
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
}
.divtable {
  font-family: Arial, Helvetica, sans-serif;
  box-shadow: 3px 3px 3px #AAAAAA;
  overflow: auto;
}
.graph {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
}
.graph tr {
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  background-color: transparent;
}
.baruar {
  border-style: none;
  background-color: white;
  text-align: right;
  padding-right: 0.5em;
  width: 300px;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: #CC0000;
  background-color: transparent;
}
.barwarn {
  border-style: none;
  background-color: white;
  text-align: right;
  padding-right: 0.5em;
  width: 300px;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  font-weight: bold;
  color: #B38E00;
  background-color: transparent;
}
.barok {
  border-style: none;
  background-color: white;
  text-align: right;
  padding-right: 0.5em;
  width: 300px;
  font-family: Arial, Helvetica, sans-serif;
  font-size: small;
  color: #25704A;
  font-weight: bold;
  background-color: transparent;
}
.baruar div {
  border-top: solid 2px #0077DD;
  background-color: #FF0000;
  border-bottom: solid 2px #002266;
  text-align: right;
  color: white;
  float: left;
  padding-top: 0;
  height: 1em;
  font-family: Arial, Helvetica, sans-serif;
  font-size: x-small;
  border-top-color: #FF9999;
  border-bottom-color: #CC0000;
}
.barwarn div {
  border-top: solid 2px #0077DD;
  background-color: #FFCC00;
  border-bottom: solid 2px #002266;
  text-align: right;
  color: white;
  float: left;
  padding-top: 0;
  height: 1em;
  font-family: Arial, Helvetica, sans-serif;
  font-size: x-small;
  border-top-color: #FFFF66;
  border-bottom-color: #ECBD00;
}
.barok div {
  border-top: solid 2px #0077DD;
  background-color: #339966;
  border-bottom: solid 2px #002266;
  text-align: right;
  color: white;
  float: left;
  padding-top: 0;
  height: 1em;
  font-family: Arial, Helvetica, sans-serif;
  font-size: x-small;
  border-top-color: #00CC66;
  border-bottom-color: #006600;
}
span.errbul {
  color: #EE0000;
  font-size: large;
  font-weight: bold;
  text-shadow: 1px 1px #AAAAAA;
}
span.warbul {
  color: #FFAA00;
  font-size: large;
  font-weight: bold;
  text-shadow: 1px 1px #AAAAAA;
}
.legend {
  font-weight: normal; 
  color: #0000FF; 
  font-size: 9pt; 
  font-weight: bold
}
.solution {
  font-weight: normal; 
  color: #0000FF; 
 font-size: small; 
  font-weight: bold
}
.regtext {
  font-weight: normal; 
 font-size: small; 
}
.btn {
	display: inline-block;
	border: #000000;
	border-style: solid; 
	border-width: 2px;
	width:190px;
	height:54px;
	border-radius: 6px;	
	background: linear-gradient(#FFFFFF, #B0B0B0);
	font-weight: bold;
	color: blue; 
	margin-top: 5px;
    margin-bottom: 5px;
    margin-right: 5px;
    margin-left: 5px;
	vertical-align: middle;
}  

</STYLE>');
  -- JS and end of header
  print_out('
<script type="text/javascript">

   function activateTab(pageId) {
	     var tabCtrl = document.getElementById(''tabCtrl'');
	       var pageToActivate = document.getElementById(pageId);
	       for (var i = 0; i < tabCtrl.childNodes.length; i++) {
	           var node = tabCtrl.childNodes[i];
	           if (node.nodeType == 1) { /* Element */
	               node.style.display = (node == pageToActivate) ? ''block'' : ''none'';
	           }
	        }
	   }

	   
   function displayItem(e, itm_id) {
     var tbl = document.getElementById(itm_id);
	 if (tbl == null) {
       if (e.innerHTML == e.innerHTML.replace(
             String.fromCharCode(9660),
             String.fromCharCode(9654))) {
       e.innerHTML =
         e.innerHTML.replace(String.fromCharCode(9654),String.fromCharCode(9660));
       }
       else {
         e.innerHTML =
           e.innerHTML.replace(String.fromCharCode(9660),String.fromCharCode(9654))
       }
     }
     else {
       if (tbl.style.display == ""){
          e.innerHTML =
             e.innerHTML.replace(String.fromCharCode(9660),String.fromCharCode(9654));
          e.innerHTML = e.innerHTML.replace("Hide SQL","Show SQL");
          tbl.style.display = "none"; }
       else {
          e.innerHTML =
            e.innerHTML.replace(String.fromCharCode(9654),String.fromCharCode(9660));
          e.innerHTML = e.innerHTML.replace("Show SQL","Hide SQL");
          tbl.style.display = ""; }
     }
   }
   
   
   //Pier: changed function to support automatic display if comming from TOC
   function displaySection(ee,itm_id) { 
 
     var tbl = document.getElementById(itm_id + ''contents'');
     var e = document.getElementById(''showhide'' + itm_id + ''contents'');

     if (tbl.style.display == ""){
        // do not hide if coming from TOC link
        if (ee != ''TOC'') {
          e.innerHTML =
          e.innerHTML.replace(String.fromCharCode(9660),String.fromCharCode(9654));
          e.innerHTML = e.innerHTML.replace("Hide SQL","Show SQL");
          tbl.style.display = "none";
        } 
     } else {
         e.innerHTML =
           e.innerHTML.replace(String.fromCharCode(9654),String.fromCharCode(9660));
         e.innerHTML = e.innerHTML.replace("Show SQL","Hide SQL");
         tbl.style.display = ""; }
     //Go to section if comming from TOC
     if (ee == ''TOC'') {
       window.location.hash=''sect'' + itm_id;
     }
   }
</script>');
-- JQuery for icons
print_out('
<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>
<script>
$(document).ready(function(){

var src = $(''img#error_ico'').attr(''src'');
$(''img.error_ico'').attr(''src'', src);

var src = $(''img#warn_ico'').attr(''src'');
$(''img.warn_ico'').attr(''src'', src);

var src = $(''img#check_ico'').attr(''src'');
$(''img.check_ico'').attr(''src'', src);
	});
</script>'); 
 
     print_out('</HEAD><BODY>');
	 
 
-- base64 icons definition	 
 --error icon
  print_out('<div style="display: none;">');
    print_out('<img id="error_ico" src="data:image/png;base64, iVBORw0KGgoAAAANSUhEUgAAABAAAAAPCAYAAADtc08vAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyppVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMi1jMDAxIDYzLjEzOTQzOSwgMjAxMC8xMC8xMi0wODo0NTozMCAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIEVsZW1lbnRzIDExLjAgV2luZG93cyIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpDNEY2MDBGRjlDRjMxMUU0OUM5M0EyMkI2RkNEMkQyMiIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDpDNEY2MDEwMDlDRjMxMUU0OUM5M0EyMkI2RkNEMkQyMiI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOkM0RjYwMEZEOUNGMzExRTQ5QzkzQTIyQjZGQ0QyRDIyIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOkM0RjYwMEZFOUNGMzExRTQ5QzkzQTIyQjZGQ0QyRDIyIi8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+X+gwwwAAAspJREFUeNpUk11Ik1EYx/9nbrNJfi6dCm1aF0poF4UaNNgs6YtIigiC6EJCAonsJgiKriOwi7qrSCOCCCWlG015Z4o6XasuJOdHtPArTbN0m9v7nvf0nNdpeeDh7OP9/Z///znnZUIIbK5GxnI5cEYHajSggspFFaYaoepWgY42IRbx32KbAgQfJfDaqfMna8s8buwqKYU1IxORqRC+B4MYHAygdeBzFwk1vROic5vADYILnYUPzjXUle9xOgB/D/iXIPjcDIQ9D8LhhO7Yjb6JWTzv+zg+vhq7FRCizRBoBKTtx9fv3a7dG5uD3t4MwTk4GdPJkty5sTMKVILu3wL3/aH+H8CVsBAhk8wsbcvOekczWP0dsCfKNjitRUFqw13EKc7hNAGvI8NtAy4xxqwmylQjM0vbukZyBz0wVXhheaYYAhI2V3qpPCQmoC8uoDzdAhPgoQT5qAcmY12tQj3uFPFyiFgZhDasCLlU/8YeH1LEdDFE2AXxtdgi+kvtYh8wRwIHpAOXNTMbYn4GetJy9HI1tGGf0Tnh92HxYvXGHKi0hIosroIezSWBLCkQjk6NQc/JMwRk2ZK2JWyt8sL+UoFGsCqLzM9GErRD3oc0KTASDn6AyHcaHWzN/+Cf1Dk+5MOOQ14UvFKM/3VhwmhUkwITJBCVAt1DAwHjrOVRqf7eLVgjN7MXqhEb9CEy0GsIqPRbIMaxDnwigRV2lrLQlxeNp93HKrUlJCbHwGn8EpaHoiWPU37mLAXtEeDpKvcvAI+Ie2+Sd5vsNLXQDev5QxaLSqBn5tDDFmhg0AjizAw1xWLAbyJ8ag14S3CIHMxvvQsVjJ2gu1Z3pCDLvT/durPIClsO18zTkThG1xLaSJSv9q3rPQR3LgNBQr4Ru8z+fxtdjKVWATcL7dlXV5Z+ZafQTGlGCwmKHqeYZur4GngIOcsk+FeAAQAH74+14hNYkgAAAABJRU5ErkJggg==" alt="error_ico">');
 --warning icon
    print_out('<img title="warning" id="warn_ico" src="data:image/png;base64, iVBORw0KGgoAAAANSUhEUgAAABAAAAAOCAYAAAAmL5yKAAAACXBIWXMAAAsTAAALEwEAmpwYAAAKT2lDQ1BQaG90b3Nob3AgSUNDIHByb2ZpbGUAAHjanVNnVFPpFj333vRCS4iAlEtvUhUIIFJCi4AUkSYqIQkQSoghodkVUcERRUUEG8igiAOOjoCMFVEsDIoK2AfkIaKOg6OIisr74Xuja9a89+bN/rXXPues852zzwfACAyWSDNRNYAMqUIeEeCDx8TG4eQuQIEKJHAAEAizZCFz/SMBAPh+PDwrIsAHvgABeNMLCADATZvAMByH/w/qQplcAYCEAcB0kThLCIAUAEB6jkKmAEBGAYCdmCZTAKAEAGDLY2LjAFAtAGAnf+bTAICd+Jl7AQBblCEVAaCRACATZYhEAGg7AKzPVopFAFgwABRmS8Q5ANgtADBJV2ZIALC3AMDOEAuyAAgMADBRiIUpAAR7AGDIIyN4AISZABRG8lc88SuuEOcqAAB4mbI8uSQ5RYFbCC1xB1dXLh4ozkkXKxQ2YQJhmkAuwnmZGTKBNA/g88wAAKCRFRHgg/P9eM4Ors7ONo62Dl8t6r8G/yJiYuP+5c+rcEAAAOF0ftH+LC+zGoA7BoBt/qIl7gRoXgugdfeLZrIPQLUAoOnaV/Nw+H48PEWhkLnZ2eXk5NhKxEJbYcpXff5nwl/AV/1s+X48/Pf14L7iJIEyXYFHBPjgwsz0TKUcz5IJhGLc5o9H/LcL//wd0yLESWK5WCoU41EScY5EmozzMqUiiUKSKcUl0v9k4t8s+wM+3zUAsGo+AXuRLahdYwP2SycQWHTA4vcAAPK7b8HUKAgDgGiD4c93/+8//UegJQCAZkmScQAAXkQkLlTKsz/HCAAARKCBKrBBG/TBGCzABhzBBdzBC/xgNoRCJMTCQhBCCmSAHHJgKayCQiiGzbAdKmAv1EAdNMBRaIaTcA4uwlW4Dj1wD/phCJ7BKLyBCQRByAgTYSHaiAFiilgjjggXmYX4IcFIBBKLJCDJiBRRIkuRNUgxUopUIFVIHfI9cgI5h1xGupE7yAAygvyGvEcxlIGyUT3UDLVDuag3GoRGogvQZHQxmo8WoJvQcrQaPYw2oefQq2gP2o8+Q8cwwOgYBzPEbDAuxsNCsTgsCZNjy7EirAyrxhqwVqwDu4n1Y8+xdwQSgUXACTYEd0IgYR5BSFhMWE7YSKggHCQ0EdoJNwkDhFHCJyKTqEu0JroR+cQYYjIxh1hILCPWEo8TLxB7iEPENyQSiUMyJ7mQAkmxpFTSEtJG0m5SI+ksqZs0SBojk8naZGuyBzmULCAryIXkneTD5DPkG+Qh8lsKnWJAcaT4U+IoUspqShnlEOU05QZlmDJBVaOaUt2ooVQRNY9aQq2htlKvUYeoEzR1mjnNgxZJS6WtopXTGmgXaPdpr+h0uhHdlR5Ol9BX0svpR+iX6AP0dwwNhhWDx4hnKBmbGAcYZxl3GK+YTKYZ04sZx1QwNzHrmOeZD5lvVVgqtip8FZHKCpVKlSaVGyovVKmqpqreqgtV81XLVI+pXlN9rkZVM1PjqQnUlqtVqp1Q61MbU2epO6iHqmeob1Q/pH5Z/YkGWcNMw09DpFGgsV/jvMYgC2MZs3gsIWsNq4Z1gTXEJrHN2Xx2KruY/R27iz2qqaE5QzNKM1ezUvOUZj8H45hx+Jx0TgnnKKeX836K3hTvKeIpG6Y0TLkxZVxrqpaXllirSKtRq0frvTau7aedpr1Fu1n7gQ5Bx0onXCdHZ4/OBZ3nU9lT3acKpxZNPTr1ri6qa6UbobtEd79up+6Ynr5egJ5Mb6feeb3n+hx9L/1U/W36p/VHDFgGswwkBtsMzhg8xTVxbzwdL8fb8VFDXcNAQ6VhlWGX4YSRudE8o9VGjUYPjGnGXOMk423GbcajJgYmISZLTepN7ppSTbmmKaY7TDtMx83MzaLN1pk1mz0x1zLnm+eb15vft2BaeFostqi2uGVJsuRaplnutrxuhVo5WaVYVVpds0atna0l1rutu6cRp7lOk06rntZnw7Dxtsm2qbcZsOXYBtuutm22fWFnYhdnt8Wuw+6TvZN9un2N/T0HDYfZDqsdWh1+c7RyFDpWOt6azpzuP33F9JbpL2dYzxDP2DPjthPLKcRpnVOb00dnF2e5c4PziIuJS4LLLpc+Lpsbxt3IveRKdPVxXeF60vWdm7Obwu2o26/uNu5p7ofcn8w0nymeWTNz0MPIQ+BR5dE/C5+VMGvfrH5PQ0+BZ7XnIy9jL5FXrdewt6V3qvdh7xc+9j5yn+M+4zw33'||
	'jLeWV/MN8C3yLfLT8Nvnl+F30N/I/9k/3r/0QCngCUBZwOJgUGBWwL7+Hp8Ib+OPzrbZfay2e1BjKC5QRVBj4KtguXBrSFoyOyQrSH355jOkc5pDoVQfujW0Adh5mGLw34MJ4WHhVeGP45wiFga0TGXNXfR3ENz30T6RJZE3ptnMU85ry1KNSo+qi5qPNo3ujS6P8YuZlnM1VidWElsSxw5LiquNm5svt/87fOH4p3iC+N7F5gvyF1weaHOwvSFpxapLhIsOpZATIhOOJTwQRAqqBaMJfITdyWOCnnCHcJnIi/RNtGI2ENcKh5O8kgqTXqS7JG8NXkkxTOlLOW5hCepkLxMDUzdmzqeFpp2IG0yPTq9MYOSkZBxQqohTZO2Z+pn5mZ2y6xlhbL+xW6Lty8elQfJa7OQrAVZLQq2QqboVFoo1yoHsmdlV2a/zYnKOZarnivN7cyzytuQN5zvn//tEsIS4ZK2pYZLVy0dWOa9rGo5sjxxedsK4xUFK4ZWBqw8uIq2Km3VT6vtV5eufr0mek1rgV7ByoLBtQFr6wtVCuWFfevc1+1dT1gvWd+1YfqGnRs+FYmKrhTbF5cVf9go3HjlG4dvyr+Z3JS0qavEuWTPZtJm6ebeLZ5bDpaql+aXDm4N2dq0Dd9WtO319kXbL5fNKNu7g7ZDuaO/PLi8ZafJzs07P1SkVPRU+lQ27tLdtWHX+G7R7ht7vPY07NXbW7z3/T7JvttVAVVN1WbVZftJ+7P3P66Jqun4lvttXa1ObXHtxwPSA/0HIw6217nU1R3SPVRSj9Yr60cOxx++/p3vdy0NNg1VjZzG4iNwRHnk6fcJ3/ceDTradox7rOEH0x92HWcdL2pCmvKaRptTmvtbYlu6T8w+0dbq3nr8R9sfD5w0PFl5SvNUyWna6YLTk2fyz4ydlZ19fi753GDborZ752PO32oPb++6EHTh0kX/i+c7vDvOXPK4dPKy2+UTV7hXmq86X23qdOo8/pPTT8e7nLuarrlca7nuer21e2b36RueN87d9L158Rb/1tWeOT3dvfN6b/fF9/XfFt1+cif9zsu72Xcn7q28T7xf9EDtQdlD3YfVP1v+3Njv3H9qwHeg89HcR/cGhYPP/pH1jw9DBY+Zj8uGDYbrnjg+OTniP3L96fynQ89kzyaeF/6i/suuFxYvfvjV69fO0ZjRoZfyl5O/bXyl/erA6xmv28bCxh6+yXgzMV70VvvtwXfcdx3vo98PT+R8IH8o/2j5sfVT0Kf7kxmTk/8EA5jz/GMzLdsAAAAgY0hSTQAAeiUAAICDAAD5/wAAgOkAAHUwAADqYAAAOpgAABdvkl/FRgAAAfBJREFUeNp8kd1L02EUxz/nt5EjlZY25ksktQWhZZEaKtoqUEYLzcLCNCQ3gq4y8QX0WvItrD8gyG6CoCzIKy8rDEQIoasoCqxFhBBERWzndDHcKtcOfHngPM/3jUfMjGxz86I8VKVDlfnBe3aG/42ZbcJsD5GluxEzM3t2J2Ld9fRne2dmOFmcXYh74nDbdVgWSvIW2OOj37tVyrIF2CSgSrS1q2//ll9LAAQCUF9LRfshBkREcla4cYGCW5cKPyR/rNlkLN9ix8Um+8Tij7Gxk3wJ+qjMWUGVgbbotTJn/TYrL7/z5j2srEKJD442UNwcZERE3FkrzHRJef72ncMVtZchPo3fl9r7dwAKjTXgL+RcXQUNWQVUGeu4Mpovn8ZBvxEOpb433GyQhAIPtDbhqS5lREQ8GzwxM6bOS2VRedVqbPy+i1fVoElIppxJZqAJGJlCX7zj7NO39iidQJWpzquTLtaG0+S5B9AzKMzNZwQchfZjOPt8jIpIIYAz0SmhmlAosq2oANYX0s6Lz4WPn2FxSTIpEtB0AA7upu5EgG4AR5WhhtNDEJ8Gy8RuqTfKfNByxNLkDaHGKtjlJSoixW5VauX1KfD80VmhNwK94X/IidTd3lLIcwgCAbcqT2ZmiapCLpj9fX79yTLg/T0AA6H+hDXGjwAAAAAASUVORK5CYII=" alt="warn_ico">');
  --check icon
    print_out('<img id="check_ico" src="data:image/png;base64, iVBORw0KGgoAAAANSUhEUgAAABAAAAANCAYAAACgu+4kAAAACXBIWXMAAAsTAAALEwEAmpwYAAAKT2lDQ1BQaG90b3Nob3AgSUNDIHByb2ZpbGUAAHjanVNnVFPpFj333vRCS4iAlEtvUhUIIFJCi4AUkSYqIQkQSoghodkVUcERRUUEG8igiAOOjoCMFVEsDIoK2AfkIaKOg6OIisr74Xuja9a89+bN/rXXPues852zzwfACAyWSDNRNYAMqUIeEeCDx8TG4eQuQIEKJHAAEAizZCFz/SMBAPh+PDwrIsAHvgABeNMLCADATZvAMByH/w/qQplcAYCEAcB0kThLCIAUAEB6jkKmAEBGAYCdmCZTAKAEAGDLY2LjAFAtAGAnf+bTAICd+Jl7AQBblCEVAaCRACATZYhEAGg7AKzPVopFAFgwABRmS8Q5ANgtADBJV2ZIALC3AMDOEAuyAAgMADBRiIUpAAR7AGDIIyN4AISZABRG8lc88SuuEOcqAAB4mbI8uSQ5RYFbCC1xB1dXLh4ozkkXKxQ2YQJhmkAuwnmZGTKBNA/g88wAAKCRFRHgg/P9eM4Ors7ONo62Dl8t6r8G/yJiYuP+5c+rcEAAAOF0ftH+LC+zGoA7BoBt/qIl7gRoXgugdfeLZrIPQLUAoOnaV/Nw+H48PEWhkLnZ2eXk5NhKxEJbYcpXff5nwl/AV/1s+X48/Pf14L7iJIEyXYFHBPjgwsz0TKUcz5IJhGLc5o9H/LcL//wd0yLESWK5WCoU41EScY5EmozzMqUiiUKSKcUl0v9k4t8s+wM+3zUAsGo+AXuRLahdYwP2SycQWHTA4vcAAPK7b8HUKAgDgGiD4c93/+8//UegJQCAZkmScQAAXkQkLlTKsz/HCAAARKCBKrBBG/TBGCzABhzBBdzBC/xgNoRCJMTCQhBCCmSAHHJgKayCQiiGzbAdKmAv1EAdNMBRaIaTcA4uwlW4Dj1wD/phCJ7BKLyBCQRByAgTYSHaiAFiilgjjggXmYX4IcFIBBKLJCDJiBRRIkuRNUgxUopUIFVIHfI9cgI5h1xGupE7yAAygvyGvEcxlIGyUT3UDLVDuag3GoRGogvQZHQxmo8WoJvQcrQaPYw2oefQq2gP2o8+Q8cwwOgYBzPEbDAuxsNCsTgsCZNjy7EirAyrxhqwVqwDu4n1Y8+xdwQSgUXACTYEd0IgYR5BSFhMWE7YSKggHCQ0EdoJNwkDhFHCJyKTqEu0JroR+cQYYjIxh1hILCPWEo8TLxB7iEPENyQSiUMyJ7mQAkmxpFTSEtJG0m5SI+ksqZs0SBojk8naZGuyBzmULCAryIXkneTD5DPkG+Qh8lsKnWJAcaT4U+IoUspqShnlEOU05QZlmDJBVaOaUt2ooVQRNY9aQq2htlKvUYeoEzR1mjnNgxZJS6WtopXTGmgXaPdpr+h0uhHdlR5Ol9BX0svpR+iX6AP0dwwNhhWDx4hnKBmbGAcYZxl3GK+YTKYZ04sZx1QwNzHrmOeZD5lvVVgqtip8FZHKCpVKlSaVGyovVKmqpqreqgtV81XLVI+pXlN9rkZVM1PjqQnUlqtVqp1Q61MbU2epO6iHqmeob1Q/pH5Z/YkGWcNMw09DpFGgsV/jvMYgC2MZs3gsIWsNq4Z1gTXEJrHN2Xx2KruY/R27iz2qqaE5QzNKM1ezUvOUZj8H45hx+Jx0TgnnKKeX836K3hTvKeIpG6Y0TLkxZVxrqpaXllirSKtRq0frvTau7aedpr1Fu1n7gQ5Bx0onXCdHZ4/OBZ3nU9lT3acKpxZNPTr1ri6qa6UbobtEd79up+6Ynr5egJ5Mb6feeb3n+hx9L/1U/W36p/VHDFgGswwkBtsMzhg8xTVxbzwdL8fb8VFDXcNAQ6VhlWGX4YSRudE8o9VGjUYPjGnGXOMk423GbcajJgYmISZLTepN7ppSTbmmKaY7TDtMx83Mz'||
	'aLN1pk1mz0x1zLnm+eb15vft2BaeFostqi2uGVJsuRaplnutrxuhVo5WaVYVVpds0atna0l1rutu6cRp7lOk06rntZnw7Dxtsm2qbcZsOXYBtuutm22fWFnYhdnt8Wuw+6TvZN9un2N/T0HDYfZDqsdWh1+c7RyFDpWOt6azpzuP33F9JbpL2dYzxDP2DPjthPLKcRpnVOb00dnF2e5c4PziIuJS4LLLpc+Lpsbxt3IveRKdPVxXeF60vWdm7Obwu2o26/uNu5p7ofcn8w0nymeWTNz0MPIQ+BR5dE/C5+VMGvfrH5PQ0+BZ7XnIy9jL5FXrdewt6V3qvdh7xc+9j5yn+M+4zw33jLeWV/MN8C3yLfLT8Nvnl+F30N/I/9k/3r/0QCngCUBZwOJgUGBWwL7+Hp8Ib+OPzrbZfay2e1BjKC5QRVBj4KtguXBrSFoyOyQrSH355jOkc5pDoVQfujW0Adh5mGLw34MJ4WHhVeGP45wiFga0TGXNXfR3ENz30T6RJZE3ptnMU85ry1KNSo+qi5qPNo3ujS6P8YuZlnM1VidWElsSxw5LiquNm5svt/87fOH4p3iC+N7F5gvyF1weaHOwvSFpxapLhIsOpZATIhOOJTwQRAqqBaMJfITdyWOCnnCHcJnIi/RNtGI2ENcKh5O8kgqTXqS7JG8NXkkxTOlLOW5hCepkLxMDUzdmzqeFpp2IG0yPTq9MYOSkZBxQqohTZO2Z+pn5mZ2y6xlhbL+xW6Lty8elQfJa7OQrAVZLQq2QqboVFoo1yoHsmdlV2a/zYnKOZarnivN7cyzytuQN5zvn//tEsIS4ZK2pYZLVy0dWOa9rGo5sjxxedsK4xUFK4ZWBqw8uIq2Km3VT6vtV5eufr0mek1rgV7ByoLBtQFr6wtVCuWFfevc1+1dT1gvWd+1YfqGnRs+FYmKrhTbF5cVf9go3HjlG4dvyr+Z3JS0qavEuWTPZtJm6ebeLZ5bDpaql+aXDm4N2dq0Dd9WtO319kXbL5fNKNu7g7ZDuaO/PLi8ZafJzs07P1SkVPRU+lQ27tLdtWHX+G7R7ht7vPY07NXbW7z3/T7JvttVAVVN1WbVZftJ+7P3P66Jqun4lvttXa1ObXHtxwPSA/0HIw6217nU1R3SPVRSj9Yr60cOxx++/p3vdy0NNg1VjZzG4iNwRHnk6fcJ3/ceDTradox7rOEH0x92HWcdL2pCmvKaRptTmvtbYlu6T8w+0dbq3nr8R9sfD5w0PFl5SvNUyWna6YLTk2fyz4ydlZ19fi753GDborZ752PO32oPb++6EHTh0kX/i+c7vDvOXPK4dPKy2+UTV7hXmq86X23qdOo8/pPTT8e7nLuarrlca7nuer21e2b36RueN87d9L158Rb/1tWeOT3dvfN6b/fF9/XfFt1+cif9zsu72Xcn7q28T7xf9EDtQdlD3YfVP1v+3Njv3H9qwHeg89HcR/cGhYPP/pH1jw9DBY+Zj8uGDYbrnjg+OTniP3L96fynQ89kzyaeF/6i/suuFxYvfvjV69fO0ZjRoZfyl5O/bXyl/erA6xmv28bCxh6+yXgzMV70VvvtwXfcdx3vo98PT+R8IH8o/2j5sfVT0Kf7kxmTk/8EA5jz/GMzLdsAAAAgY0hSTQAAeiUAAICDAAD5/wAAgOkAAHUwAADqYAAAOpgAABdvkl/FRgAAAMRJREFUeNqkkjEOgkAQRd96GY7gAajEWBALEzXRhHAJqr0Dd/AqJFZa2dnZSGVjY/EtkEUC0UU3mWYz7/3J7hhJ/HNGQ5rN1lizNjILY92lJK9ig2WFinshYkRILonh8J6qIgQEv8NjdsCsakqxpIgU24GXH2AIHFw8Cr1LWsmHfrj6wRouUXbLRIKYk7vk4wuedOFaUI1f0kg8kp3AvUGCuCDOKLtmX5NbAknUY3OigaPPcGcPmJIT+8O9i0RI7gtL4jkALy1qUf+xbKAAAAAASUVORK5CYII=" alt="check_ico">');
   print_out('</div>');

END print_page_header;
	 
----------------------------------------------------------------
-- Prints report title section                                --
-- ===========================                                --
-- To change look & feel:                                     --
-- Change css class divtitle which is the container box and   --
-- defines the backgrownd color and first line font           --
-- Change css class divtitle1 which defines the font on the   --
-- testname (second line)                                     --
----------------------------------------------------------------

PROCEDURE print_rep_title(p_analyzer_title varchar2) is
BEGIN

  -- Print title
  -- PSD #3
  print_page_header;
  print_out('<!----------------- Title ----------------->
<div class="TitleBar">
<div class="TitleImg"><a href="https://support.oracle.com/rs?type=doc%5C&amp;id=432.1" target="_blank"><img src="https://blogs.oracle.com/ebs/resource/Proactive/PSC_Logo.jpg" title="Click here to see other helpful Oracle Proactive Tools" alt="Proactive Services Banner" border="0" height="60" width="180"></a></div>
    <div class="Title1">'|| p_analyzer_title || ' Analyzer Report' ||'</div>
    <div class="Title2">Compiled using version ' ||  g_rep_info('File Version') || ' / Latest version: ' || '<a href="https://support.oracle.com/oip/faces/secure/km/DownloadAttachment.jspx?attachid=1525670.1:POAPPANALYZER">
<img border="0" src="https://blogs.oracle.com/ebs/resource/Proactive/po_approval_latest_version.gif" title="Click here to download the latest version of PO Approval Analyzer" alt="Latest Version Icon"></a></div>
</div>
<br>');
END print_rep_title;


----------------------------------------------------------------
-- Prints Report Information placeholder                      --
----------------------------------------------------------------

PROCEDURE print_toc(
  ptoctitle varchar2 DEFAULT 'Report Information') IS
  l_key  VARCHAR2(255);
  l_html VARCHAR2(4000);
BEGIN
  g_sections.delete;
    print_out('<!------------------ TOC ------------------>
    <div class="divSection">');
  -- Print Run details and Parameters Section
  print_out('<div class="divItem" id="runinfo"><div class="divItemTitle">' ||
    'Report Information</div>');
	print_out('<span class="legend">Legend: &nbsp;&nbsp;<img class="error_ico"> Error &nbsp;&nbsp;<img class="warn_ico"> Warning &nbsp;&nbsp;<img class="check_ico"> Passed Check</span>');
	-- print_out('<p>');  
  print_out(
   '<table width="100%" class="graph"><tbody> 
      <tr class="top"><td width="30%"><p>
      <a class="detail" href="javascript:;" onclick="displayItem(this,''RunDetails'');"><font color="#0066CC">
      &#9654; Execution Details</font></a></p>
      <table class="table1" id="RunDetails" style="display:none">
      <tbody>');
  -- Loop and print values
  l_key := g_rep_info.first;
  WHILE l_key IS NOT NULL LOOP
    print_out('<tr><th class="rep">'||l_key||'</th><td>'||
      g_rep_info(l_key)||'</td></tr>');
    l_key := g_rep_info.next(l_key);
  END LOOP;
  print_out('</tbody></table></td>');
  print_out('<td width="30%"><p>
    <a class="detail" href="javascript:;" onclick="displayItem(this,''Parameters'');"><font color="#0066CC">
       &#9654; Parameters</font></a></p>
       <table class="table1" id="Parameters" style="display:none">
       <tbody>');
  l_key := g_parameters.first;
  WHILE l_key IS NOT NULL LOOP
    print_out('<tr><th class="rep">'||l_key||'</th><td>'||
      g_parameters(l_key)||'</td></tr>');
    l_key := g_parameters.next(l_key);
  END LOOP;
    print_out('</tbody></table></td>');  
    print_out('<td width="30%"><p>
    <div id="ExecutionSummary1"><a class="detail" href="javascript:;" onclick="displayItem(this,''ExecutionSummary2'');"><font color="#0066CC">&#9654; Execution Summary</font></a> </div>
    <div id="ExecutionSummary2" style="display:none">   </div>');   
 
  print_out('</td></tr></table>
    </div><br/>');

  -- Print out the Table of Contents holder
  print_out('<div class="divItem" id="toccontent"><div class="divItemTitle">' ||
    ptoctitle || '</div></div>
	<div align="center">
<a class="detail" onclick="opentabs();" href="javascript:;"><font color="#0066CC"><br>Show All Sections</font></a> &nbsp;&nbsp;/ &nbsp;&nbsp;
<a class="detail" onclick="closetabs();" href="javascript:;"><font color="#0066CC">Hide All Sections</font></a>
</div>
	</div></div><br><br>');
END print_toc;

----------------------------------------------------------------
-- Prints report TOC contents at end of script                --
----------------------------------------------------------------

PROCEDURE print_toc_contents(
     p_err_label  VARCHAR2 DEFAULT 'Checks Failed - Critical',
     p_warn_label VARCHAR2 DEFAULT 'Checks Failed - Warning',
     p_pass_label VARCHAR2 DEFAULT 'Checks Passed') IS

  l_action_req BOOLEAN := false;
  l_cnt_err  NUMBER := 0;
  l_cnt_warn NUMBER := 0;
  l_cnt_succ NUMBER := 0;
  l_tot_cnt  NUMBER;
  l_loop_count NUMBER;
     
BEGIN
 
  -- Script tag, assign old content to var, reassign old content and new stuff
  print_out('
<script type="text/javascript">
  var auxs;
  auxs = document.getElementById("toccontent").innerHTML;
  document.getElementById("toccontent").innerHTML = auxs + ');

  l_loop_count := g_sections.count;
	
  -- Loop through sections and generate HTML
  FOR i in 1 .. l_loop_count LOOP
      -- Add to counts
      l_cnt_err := l_cnt_err + g_sections(i).error_count;
      l_cnt_warn := l_cnt_warn + g_sections(i).warn_count;
      l_cnt_succ := l_cnt_succ + g_sections(i).success_count;
      -- Print Section name
		print_out('"<button class=''btn'' OnClick=activateTab(''page' || to_char(i) || ''')>' ||     
        g_sections(i).name || '" +');
      -- Print if section in error, warning or successful
      IF g_sections(i).result ='E' THEN 
	  print_out('" <img class=''error_ico''>" +');
        l_action_req := true;
		-- g_retcode := 1;
      ELSIF g_sections(i).result ='W' THEN
        print_out('" <img class=''warn_ico''>" +');
        l_action_req := true;
		-- g_retcode := 1;
	  ELSIF g_sections(i).result ='S' THEN
        print_out('" <img class=''check_ico''>" +');
        l_action_req := true;
		--g_retcode := 0;
      -- Print end of button
       
    END IF;
	print_out('"</button>" +');
  END LOOP;
  -- End the div
  print_out('"</div>";');
  -- End
  print_out('activateTab(''page1'');');
  
  -- Loop through sections and generate HTML for start sections
    FOR i in 1 .. l_loop_count LOOP
		print_out('auxs = document.getElementById("sect_title'||i||'").innerHTML;
				document.getElementById("sect_title'||i||'").innerHTML = auxs + ');
		if g_sections(i).error_count>0 and g_sections(i).warn_count>0 then
				print_out(' "'||g_sections(i).error_count||' <img class=''error_ico''>  '||g_sections(i).warn_count||' <img class=''warn_ico''> ";');
			elsif g_sections(i).error_count>0 then
				print_out(' "'||g_sections(i).error_count||' <img class=''error_ico''> ";');
			elsif g_sections(i).warn_count>0 then
				print_out(' "'||g_sections(i).warn_count||' <img class=''warn_ico''> ";');
			elsif g_sections(i).result ='S' then
				print_out(' " <img class=''check_ico''> ";');
			else
				print_out(' " ";');
			end if;						
	END LOOP;

	-- Loop through sections and generate HTML for execution summary
	print_out('auxs = document.getElementById("ExecutionSummary1").innerHTML;
				document.getElementById("ExecutionSummary1").innerHTML = auxs + ');
	if l_cnt_err>0 and l_cnt_warn>0 then
		print_out(' "('||l_cnt_err||' <img class=''error_ico''> '||l_cnt_warn||' <img class=''warn_ico''>)</A>";');
	elsif l_cnt_err>0 and l_cnt_warn=0 then
		print_out(' "(<img class=''error_ico''>'||l_cnt_err||')</A>";');
	elsif l_cnt_err=0 and l_cnt_warn>0 then
		print_out(' "(<img class=''warn_ico''>'||l_cnt_warn||')</A>";');
	elsif l_cnt_err=0 and l_cnt_warn=0 then
		print_out(' "(<img class=''check_ico''> No issues reported)</A>";');
	end if;
		
	print_out('auxs = document.getElementById("ExecutionSummary2").innerHTML;
				document.getElementById("ExecutionSummary2").innerHTML = auxs + ');
	print_out('" <table width=''100%'' class=''table1''><TR><TH class=''rep''><B>Section</B></TH><TH class=''rep''><B>Errors</B></TH><TH class=''rep''><B>Warnings</B></TH></TR>"+');
	  
    FOR i in 1 .. l_loop_count LOOP
			print_out('"<TR><TH class=''rep''><A class=detail onclick=activateTab(''page' || to_char(i) || '''); href=''javascript:;''>'||g_sections(i).name||'</A> "+');
			if g_sections(i).error_count>0 then
				print_out(' "<img class=''error_ico''>"+');
			elsif g_sections(i).warn_count>0 then
				print_out(' "<img class=''warn_ico''>"+');	
			elsif g_sections(i).result ='S' then
				print_out(' "<img class=''check_ico''>"+');
			end if;	
			print_out('"</TH><TD>'||g_sections(i).error_count||'</TD><TD>'||g_sections(i).warn_count||'</TD> </TR>"+'); 
	END LOOP;
	print_out('" </TABLE></div>";'); 
		
	print_out('function openall()
	{var txt = "restable";
	 var i;
	 var x=document.getElementById(''restable1'');
	 for (i=0;i<='||g_sig_id||';i++)  
	  {
	  x = document.getElementById(txt.concat(i.toString(),''b''));  
	       if (!(x == null ))
		    {x.innerHTML = x.innerHTML.replace(String.fromCharCode(9654),String.fromCharCode(9660));
	         x.innerHTML = x.innerHTML.replace("Show SQL","Hide SQL"); 
			 }
	  x=document.getElementById(txt.concat(i.toString())); 
	    if (!(x == null ))
		  {document.getElementById(txt.concat(i.toString())).style.display = ''''; }
	  }
	}
	 
	function closeall()
	{var txt = "restable";
	var txt2 = "tbitm";
	var i;
	var x=document.getElementById(''restable1'');
	for (i=0;i<='||g_sig_id||';i++)  
	{	
			x=document.getElementById(txt2.concat(i.toString()));   
	       if (!(x == null ))
		    {document.getElementById(txt2.concat(i.toString())).style.display = ''none'';}
		   x = document.getElementById(txt2.concat(i.toString(),''b''));  
			   if (!(x == null ))
				{x.innerHTML = x.innerHTML.replace("Hide SQL","Show SQL");}
				 
			x = document.getElementById(txt.concat(i.toString(),''b''));  
	       if (!(x == null )){x.innerHTML = x.innerHTML.replace(String.fromCharCode(9660),String.fromCharCode(9654)); }
			
			x=document.getElementById(txt.concat(i.toString())); 
	       if (!(x == null )){document.getElementById(txt.concat(i.toString())).style.display = ''none'';}  	
		   }}
		 
	 function opentabs() {
     var tabCtrl = document.getElementById(''tabCtrl'');       
       for (var i = 0; i < tabCtrl.childNodes.length; i++) {
           var node = tabCtrl.childNodes[i];
           if (node.nodeType == 1 && node.toString() != ''[object HTMLScriptElement]'') { /* Element */
               node.style.display =  ''block'' ;
           }
        }
   }
   
    function closetabs() {
     var tabCtrl = document.getElementById(''tabCtrl'');       
       for (var i = 0; i < tabCtrl.childNodes.length; i++) {
           var node = tabCtrl.childNodes[i];
           if (node.nodeType == 1) { /* Element */
               node.style.display =  ''none'' ;
           }
        }
   }
		</script> ');	
	
EXCEPTION WHEN OTHERS THEN
  print_log('Error in print_toc_contents: '||sqlerrm);
  raise;
END print_toc_contents;

----------------------------------------------------------------
-- Evaluates if a rowcol meets desired criteria               --
----------------------------------------------------------------

FUNCTION evaluate_rowcol(p_oper varchar2, p_val varchar2, p_colv varchar2) return boolean is
  x   NUMBER;
  y   NUMBER;
  n   boolean := true;
BEGIN
  -- Attempt to convert to number the column value, otherwise proceed as string
  BEGIN
    x := to_number(p_colv);
    y := to_number(p_val);
  EXCEPTION WHEN OTHERS THEN
    n := false;
  END;
  -- Compare
  IF p_oper = '=' THEN
    IF n THEN
      return x = y;
    ELSE
      return p_val = p_colv;
    END IF;
  ELSIF p_oper = '>' THEN
    IF n THEN
      return x > y;
    ELSE
      return p_colv > p_val;
    END IF;
  ELSIF p_oper = '<' THEN
    IF n THEN
      return x < y;
    ELSE
      return p_colv < p_val;
    END IF;
  ELSIF p_oper = '<=' THEN
    IF n THEN
      return x <= y;
    ELSE
      return p_colv <= p_val;
    END IF;
  ELSIF p_oper = '>=' THEN
    IF n THEN
      return x >= y;
    ELSE
      return p_colv >= p_val;
    END IF;
  ELSIF p_oper = '!=' OR p_oper = '<>' THEN
    IF n THEN
      return x != y;
    ELSE
      return p_colv != p_val;
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in evaluate_rowcol');
  raise;
END evaluate_rowcol;

----------------------------------------------------------------------
-- Diag specific procedure (kluge) has to be here because calling from
-- process_signature results 
----------------------------------------------------------------------

PROCEDURE verify_approver(p_empid IN NUMBER) IS
  l_return_status VARCHAR2(1);
  l_return_code   VARCHAR2(25);
  l_exception_msg VARCHAR2(2000);
  l_auth_fail_msg VARCHAR2(2000);
  l_doc_id        NUMBER;
BEGIN
  IF p_empid <> g_curr_empid OR g_curr_empid is null THEN
    IF g_sql_tokens('##$$TRXTP$$##') = 'RELEASE' THEN
      l_doc_id := to_number(g_sql_tokens('##$$RELID$$##'));
    ELSE
      l_doc_id := to_number(g_sql_tokens('##$$DOCID$$##'));
    END IF;
    g_curr_empid := p_empid;
    po_document_action_pvt.verify_authority(
      p_document_id => l_doc_id,
      p_document_type => g_sql_tokens('##$$TRXTP$$##'),
      p_document_subtype => g_sql_tokens('##$$SUBTP$$##'),
      p_employee_id => p_empid,
      x_return_status => l_return_status,
      x_return_code => l_return_code,
      x_exception_msg => l_exception_msg,
      x_auth_failed_msg  => l_auth_fail_msg);
    g_app_results('STATUS') := l_return_status;
    g_app_results('CODE') := l_return_code;
    g_app_results('EXC_MSG') := l_exception_msg;
    g_app_results('FAIL_MSG') := l_auth_fail_msg;
  END IF;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in verify_approver: '||sqlerrm);
  raise;
END verify_approver;

---------------------------------------------
-- Expand [note] or {patch} tokens         --
---------------------------------------------

FUNCTION expand_links(p_str VARCHAR2) return VARCHAR2 IS
  l_str VARCHAR2(32000);
  l_s VARCHAR2(20);
Begin
  -- Assign to working variable
  l_str := p_str;
  -- First deal with patches
  l_str := regexp_replace(l_str,'({)([0-9]*)(})',
    '<a target="_blank" href="'||g_mos_patch_url||'\2">Patch \2</a>',1,0);
  -- Same for notes
  l_str := regexp_replace(l_str,'(\[)([0-9]*\.[0-9])(\])',
    '<a target="_blank" href="'||g_mos_doc_url||'\2">Doc ID \2</a>',1,0);
  return l_str;
END expand_links;

--------------------------------------------
-- Prepare the SQL with the substitution values
--------------------------------------------

FUNCTION prepare_sql(
  p_signature_sql IN VARCHAR2
  ) RETURN VARCHAR2 IS
  l_sql VARCHAR2(32767);
  l_key VARCHAR2(255);
BEGIN
  -- Assign signature to working variable
  l_sql := p_signature_sql;
  --  Build the appropriate SQL replacing all applicable values
  --  with the appropriate parameters
  l_key := g_sql_tokens.first;
  WHILE l_key is not null LOOP
    l_sql := replace(l_sql, l_key, g_sql_tokens(l_key));
    l_key := g_sql_tokens.next(l_key);
  END LOOP;
  RETURN l_sql;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in prepare_sql');
  raise;
END prepare_sql;

----------------------------------------------------------------
-- Set partial section result                                 --
----------------------------------------------------------------
PROCEDURE set_item_result(result varchar2) is
BEGIN

  IF g_sections(g_sections.last).result in ('U','I') THEN
      g_sections(g_sections.last).result := result;
  ELSIF g_sections(g_sections.last).result = 'S' THEN
    IF result in ('E','W') THEN
      g_sections(g_sections.last).result := result;
    END IF;  
  ELSIF g_sections(g_sections.last).result = 'W' THEN
    IF result = 'E' THEN
      g_sections(g_sections.last).result := result;
    END IF;
  END IF;
  -- Set counts
  IF result = 'S' THEN
    g_sections(g_sections.last).success_count :=
       g_sections(g_sections.last).success_count + 1;
  ELSIF result = 'W' THEN
    g_sections(g_sections.last).warn_count :=
       g_sections(g_sections.last).warn_count + 1;
  ELSIF result = 'E' THEN
    g_sections(g_sections.last).error_count :=
       g_sections(g_sections.last).error_count + 1;
  END IF;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in set_item_result: '||sqlerrm);
  raise;
END set_item_result;

----------------------------------------------------------------------
-- Runs a single SQL using DBMS_SQL returns filled tables
-- Precursor to future run_signature which will call this and
-- the print api. For now calls are manual.
----------------------------------------------------------------------

PROCEDURE run_sig_sql(
   p_raw_sql      IN  VARCHAR2,     -- SQL in the signature may require substitution
   p_col_rows     OUT COL_LIST_TBL, -- signature SQL column names
   p_col_headings OUT VARCHAR_TBL, -- signature SQL row values
   p_limit_rows   IN  VARCHAR2 DEFAULT 'Y') IS

  l_sql            VARCHAR2(32767);
  c                INTEGER;
  l_rows_fetched   NUMBER;
  l_step           VARCHAR2(20);
  l_col_rows       COL_LIST_TBL := col_list_tbl();
  l_col_headings   VARCHAR_TBL := varchar_tbl();
  l_col_cnt        INTEGER;
  l_desc_rec_tbl   DBMS_SQL.DESC_TAB2;

BEGIN
  -- Prepare the Signature SQL
  l_step := '10';
  l_sql := prepare_sql(p_raw_sql);
  -- Add SQL with substitution to attributes table
  l_step := '20';
  c := dbms_sql.open_cursor;
  l_step := '30';
  DBMS_SQL.PARSE(c, l_sql, DBMS_SQL.NATIVE);
  -- Get column count and descriptions
  l_step := '40';
  DBMS_SQL.DESCRIBE_COLUMNS2(c, l_col_cnt, l_desc_rec_tbl);
  -- Register arrays to bulk collect results and set headings
  l_step := '50';
  FOR i IN 1..l_col_cnt LOOP
    l_step := '50.1.'||to_char(i);
    l_col_headings.extend();
    l_col_headings(i) := initcap(replace(l_desc_rec_tbl(i).col_name,'|','<br>'));
    l_col_rows.extend();
    dbms_sql.define_array(c, i, l_col_rows(i), g_max_output_rows, 1);
  END LOOP;
  -- Execute and Fetch
  l_step := '60';
  get_current_time(g_query_start_time);
  l_rows_fetched := DBMS_SQL.EXECUTE(c);
  l_rows_fetched := DBMS_SQL.FETCH_ROWS(c);
  debug(' Rows fetched: '||to_char(l_rows_fetched));
  l_step := '70';
  IF l_rows_fetched > 0 THEN
    FOR i in 1..l_col_cnt LOOP
      l_step := '70.1.'||to_char(i);
      DBMS_SQL.COLUMN_VALUE(c, i, l_col_rows(i));
    END LOOP;
  END IF;
  IF nvl(p_limit_rows,'Y') = 'N' THEN
    WHILE l_rows_fetched = g_max_output_rows LOOP
      l_rows_fetched := DBMS_SQL.FETCH_ROWS(c);
      debug(' Rows fetched: '||to_char(l_rows_fetched));
      FOR i in 1..l_col_cnt LOOP
        l_step := '70.2.'||to_char(i);
        DBMS_SQL.COLUMN_VALUE(c, i, l_col_rows(i));
      END LOOP;
    END LOOP;
  END IF;
  g_query_elapsed := stop_timer(g_query_start_time);
--  g_query_total := g_query_total + g_query_elapsed;

  -- Close cursor
  l_step := '80';
  IF dbms_sql.is_open(c) THEN
    dbms_sql.close_cursor(c);
  END IF;
  -- Set out parameters
  p_col_headings := l_col_headings;
  p_col_rows := l_col_rows;
EXCEPTION
  WHEN OTHERS THEN
    print_error('PROGRAM ERROR<br />
      Error in run_sig_sql at step '||
      l_step||': '||sqlerrm||'<br/>
      See the log file for additional details<br/>');
    print_log('Error at step '||l_step||' in run_sig_sql running: '||l_sql);
    print_log('Error: '||sqlerrm);
    l_col_cnt := -1;
    IF dbms_sql.is_open(c) THEN
      dbms_sql.close_cursor(c);
    END IF;
    g_errbuf := 'toto '||l_step;
END run_sig_sql;

PROCEDURE generate_hidden_xml(
  p_sig_id          VARCHAR2,
  p_sig             SIGNATURE_REC, -- Name of signature item
  p_col_rows        COL_LIST_TBL,  -- signature SQL row values
  p_col_headings    VARCHAR_TBL)    -- signature SQL column names       
IS

l_hidden_xml_doc       XMLDOM.DOMDocument;
l_hidden_xml_node      XMLDOM.DOMNode;
l_diagnostic_element   XMLDOM.DOMElement;
l_diagnostic_node      XMLDOM.DOMNode;
l_issues_node          XMLDOM.DOMNode;
l_signature_node       XMLDOM.DOMNode;
l_signature_element    XMLDOM.DOMElement;
l_node                 XMLDOM.DOMNode;
l_row_node             XMLDOM.DOMNode;
l_failure_node         XMLDOM.DOMNode;
l_run_details_node     XMLDOM.DOMNode;
l_run_detail_data_node XMLDOM.DOMNode;
l_detail_element       XMLDOM.DOMElement;
l_detail_node          XMLDOM.DOMNode;
l_detail_name_attribute XMLDOM.DOMAttr;
l_parameters_node      XMLDOM.DOMNode;
l_parameter_node       XMLDOM.DOMNode;
l_col_node             XMLDOM.DOMNode;
l_parameter_element    XMLDOM.DOMElement;
l_col_element          XMLDOM.DOMElement;
l_param_name_attribute XMLDOM.DOMAttr;
l_failure_element      XMLDOM.DOMElement;
l_sig_id_attribute     XMLDOM.DOMAttr;
l_col_name_attribute   XMLDOM.DOMAttr;
l_row_attribute        XMLDOM.DOMAttr;
l_key                  VARCHAR2(255);
l_match                VARCHAR2(1);
l_rows                 NUMBER;
l_value                VARCHAR2(2000);


BEGIN

l_hidden_xml_doc := g_hidden_xml;

IF (XMLDOM.isNULL(l_hidden_xml_doc)) THEN
    
   --PO CUSTOM START 
   g_reset_node := null;
   --PO CUSTOM END
   l_hidden_xml_doc := XMLDOM.newDOMDocument;
   l_hidden_xml_node := XMLDOM.makeNode(l_hidden_xml_doc);
   l_diagnostic_node := XMLDOM.appendChild(l_hidden_xml_node,XMLDOM.makeNode(XMLDOM.createElement(l_hidden_xml_doc,'diagnostic')));

   l_run_details_node := XMLDOM.appendChild(l_diagnostic_node,XMLDOM.makeNode(XMLDOM.createElement(l_hidden_xml_doc,'run_details')));   
   l_key := g_rep_info.first;
   WHILE l_key IS NOT NULL LOOP
   
     l_detail_element := XMLDOM.createElement(l_hidden_xml_doc,'detail');
     l_detail_node := XMLDOM.appendChild(l_run_details_node,XMLDOM.makeNode(l_detail_element));
     l_detail_name_attribute:=XMLDOM.setAttributeNode(l_detail_element,XMLDOM.createAttribute(l_hidden_xml_doc,'name'));
     XMLDOM.setAttribute(l_detail_element, 'name', l_key);
     l_node := XMLDOM.appendChild(l_detail_node,XMLDOM.makeNode(XMLDOM.createTextNode(l_hidden_xml_doc,g_rep_info(l_key))));

     l_key := g_rep_info.next(l_key);

   END LOOP;

   l_parameters_node := XMLDOM.appendChild(l_diagnostic_node,XMLDOM.makeNode(XMLDOM.createElement(l_hidden_xml_doc,'parameters')));
   l_key := g_parameters.first;
   WHILE l_key IS NOT NULL LOOP

     l_parameter_element := XMLDOM.createElement(l_hidden_xml_doc,'parameter');
     l_parameter_node := XMLDOM.appendChild(l_parameters_node,XMLDOM.makeNode(l_parameter_element));
     l_param_name_attribute:=XMLDOM.setAttributeNode(l_parameter_element,XMLDOM.createAttribute(l_hidden_xml_doc,'name'));
     XMLDOM.setAttribute(l_parameter_element, 'name', l_key);
     l_node := XMLDOM.appendChild(l_parameter_node,XMLDOM.makeNode(XMLDOM.createTextNode(l_hidden_xml_doc,g_parameters(l_key))));

     l_key := g_parameters.next(l_key);


   END LOOP;
   
   l_issues_node := XMLDOM.appendChild(l_diagnostic_node,XMLDOM.makeNode(XMLDOM.createElement(l_hidden_xml_doc,'issues')));   

END IF;


 IF p_sig_id IS NOT NULL THEN

   l_issues_node := XMLDOM.getLastChild(XMLDOM.getFirstChild(XMLDOM.makeNode(l_hidden_xml_doc)));

   l_signature_element := XMLDOM.createElement(l_hidden_xml_doc,'signature');
   l_sig_id_attribute := XMLDOM.setAttributeNode(l_signature_element,XMLDOM.createAttribute(l_hidden_xml_doc,'id'));
   l_signature_node := XMLDOM.appendChild(l_issues_node,XMLDOM.makeNode(l_signature_element));
   XMLDOM.setAttribute(l_signature_element, 'id',p_sig_id);

   IF p_sig.limit_rows='Y' THEN
      l_rows := least(g_max_output_rows,p_col_rows(1).COUNT,50);
   ELSE
      l_rows := least(p_col_rows(1).COUNT,50);
   END IF;
   
   FOR i IN 1..l_rows LOOP

      l_failure_element := XMLDOM.createElement(l_hidden_xml_doc,'failure');
      l_row_attribute := XMLDOM.setAttributeNode(l_failure_element,XMLDOM.createAttribute(l_hidden_xml_doc,'row'));     
      l_failure_node := XMLDOM.appendChild(l_signature_node,XMLDOM.makeNode(l_failure_element));
      XMLDOM.setAttribute(l_failure_element, 'row', i);   
    
      FOR j IN 1..p_col_headings.count LOOP
 
         l_col_element := XMLDOM.createElement(l_hidden_xml_doc,'column');
         l_col_name_attribute := XMLDOM.setAttributeNode(l_col_element,XMLDOM.createAttribute(l_hidden_xml_doc,'name'));
         l_col_node := XMLDOM.appendChild(l_failure_node,XMLDOM.makeNode(l_col_element));
         XMLDOM.setAttribute(l_col_element, 'name',p_col_headings(j));
 
         l_value := p_col_rows(j)(i);

         IF p_sig_id = 'REC_PATCH_CHECK' THEN
            --PO CUSTOM START
            IF p_col_headings(j) = 'Applied' AND l_value='Yes' THEN
               l_failure_node:=DBMS_XMLDOM.removeChild(l_signature_node,l_failure_node);
               exit;               
            ELSIF p_col_headings(j) = 'Patch' THEN
            --PO CUSTOM END
               l_value := replace(replace(p_col_rows(j)(i),'{'),'}');
            ELSIF p_col_headings(j) = 'Note' THEN
               l_value := replace(replace(p_col_rows(j)(i),'['),']');
            END IF;
         END IF;
         
		 -- Rtrim the column value if blanks are not to be preserved
          IF NOT g_preserve_trailing_blanks THEN
            l_value := RTRIM(l_value, ' ');
          END IF;
         l_node := XMLDOM.appendChild(l_col_node,XMLDOM.makeNode(XMLDOM.createTextNode(l_hidden_xml_doc,l_value)));

      END LOOP;
    END LOOP;
    
    --PO CUSTOM START
    --remove the retry/reset sigs if any other solutions are offered.
    --this will work b/c some sig (ie, recommended patches) will always be added after the retry/reset was added
    --if it becomes possible for this to be the last added sig, need to enhance this to handle that case.
    IF p_sig_id IN ('Note390023.1_case_PO9','Note390023.1_case_REL6','Note390023.1_case_REQ8') THEN
       g_reset_node := l_signature_node;
    ELSIF NOT DBMS_XMLDOM.ISNULL(g_reset_node) AND p_sig_id NOT IN ('REC_PATCH_CHECK','PO_INVALIDS') THEN
       g_reset_node:=DBMS_XMLDOM.removeChild(l_issues_node,g_reset_node);        
       g_reset_node:=null;
    END IF;
    --PO CUSTOM END
    
  END IF;  

  g_hidden_xml := l_hidden_xml_doc;


END generate_hidden_xml;


PROCEDURE print_hidden_xml
IS

l_hidden_xml_clob      clob;
l_offset               NUMBER := 1;
l_length               NUMBER;

l_node_list            XMLDOM.DOMNodeList;
l_node_length          NUMBER;

BEGIN

IF XMLDOM.isNULL(g_hidden_xml) THEN

   generate_hidden_xml(p_sig_id => null,
                       p_sig => null,
                       p_col_headings => null,
                       p_col_rows => null);
                       
END IF;                      

dbms_lob.createtemporary(l_hidden_xml_clob, true);

--print CLOB
XMLDOM.WRITETOCLOB(g_hidden_xml, l_hidden_xml_clob); 

print_out('<!-- ######BEGIN DX SUMMARY######','Y');

LOOP
   EXIT WHEN (l_offset > dbms_lob.getlength(l_hidden_xml_clob) OR dbms_lob.getlength(l_hidden_xml_clob)=0);
   
      print_out(dbms_lob.substr(l_hidden_xml_clob,2000, l_offset),'N');

      l_offset := l_offset + 2000;
      
   END LOOP;
   
print_out('######END DX SUMMARY######-->','Y');  --should be a newline here

dbms_lob.freeTemporary(l_hidden_xml_clob);      
XMLDOM.FREEDOCUMENT(g_hidden_xml);

END print_hidden_xml;

----------------------------------------------------------------
-- Once a signature has been run, evaluates and prints it     --
----------------------------------------------------------------
FUNCTION process_signature_results(
  p_sig_id          VARCHAR2,      -- signature id
  p_sig             SIGNATURE_REC, -- Name of signature item
  p_col_rows        COL_LIST_TBL,  -- signature SQL row values
  p_col_headings    VARCHAR_TBL,    -- signature SQL column names
  p_is_child        BOOLEAN    DEFAULT FALSE
  ) RETURN VARCHAR2 IS             -- returns 'E','W','S','I'

  l_sig_fail      BOOLEAN := false;
  l_row_fail      BOOLEAN := false;
  l_fail_flag     BOOLEAN := false;
  l_html          VARCHAR2(32767) := null;
  l_column        VARCHAR2(255) := null;
  l_operand       VARCHAR2(3);
  l_value         VARCHAR2(4000);
  l_step          VARCHAR2(255);
  l_i             VARCHAR2(255);
  l_curr_col      VARCHAR2(255) := NULL;
  l_curr_val      VARCHAR2(4000) := NULL;
  l_print_sql_out BOOLEAN := true;
  l_inv_param     EXCEPTION;
  l_rows_fetched  NUMBER := p_col_rows(1).count;
  l_printing_cols NUMBER := 0;
  l_is_child      BOOLEAN;
  l_error_type    VARCHAR2(1); 

BEGIN
  -- Validate parameters which have fixed values against errors when
  -- defining or loading signatures
  l_is_child := p_is_child;
  l_step := 'Validate parameters';
  IF (NOT l_is_child) THEN
     g_family_result := '';
  END IF;


  IF (p_sig.fail_condition NOT IN ('RSGT1','RS','NRS')) AND
     ((instr(p_sig.fail_condition,'[') = 0) OR
      (instr(p_sig.fail_condition,'[',1,2) = 0) OR
      (instr(p_sig.fail_condition,']') = 0) OR
      (instr(p_sig.fail_condition,']',1,2) = 0))  THEN
    print_log('Invalid value or format for failure condition: '||
      p_sig.fail_condition);
    raise l_inv_param;
  ELSIF p_sig.print_condition NOT IN ('SUCCESS','FAILURE','ALWAYS','NEVER') THEN
    print_log('Invalid value for print_condition: '||p_sig.print_condition);
    raise l_inv_param;
  ELSIF p_sig.fail_type NOT IN ('E','W','I') THEN
    print_log('Invalid value for fail_type: '||p_sig.fail_type);
    raise l_inv_param;
  ELSIF p_sig.print_sql_output NOT IN ('Y','N','RS') THEN
    print_log('Invalid value for print_sql_output: '||p_sig.print_sql_output);
    raise l_inv_param;
  ELSIF p_sig.limit_rows NOT IN ('Y','N') THEN
    print_log('Invalid value for limit_rows: '||p_sig.limit_rows);
    raise l_inv_param;
  ELSIF p_sig.print_condition in ('ALWAYS','SUCCESS') AND
        p_sig.success_msg is null AND p_sig.print_sql_output = 'N' THEN
    print_log('Invalid parameter combination.');
    print_log('print_condition/success_msg/print_sql_output: '||
      p_sig.print_condition||'/'||nvl(p_sig.success_msg,'null')||
      '/'||p_sig.print_sql_output);
    print_log('When printing on success either success msg or SQL output '||
        'printing should be enabled.');
    raise l_inv_param;
  END IF;
  -- For performance sake: first make trivial evaluations of success
  -- and if no need to print just return
  l_step := '10';
  IF (p_sig.print_condition IN ('NEVER','FAILURE') AND
	 ((p_sig.fail_condition = 'RSGT1' AND l_rows_fetched = 0) OR
      (p_sig.fail_condition = 'RS' AND l_rows_fetched = 0) OR
      (p_sig.fail_condition = 'NRS' AND l_rows_fetched > 0))) THEN
    IF p_sig.fail_type = 'I' THEN
      return 'I';
    ELSE
      return 'S';
    END IF;
  ELSIF (p_sig.print_condition IN ('NEVER','SUCCESS') AND
		((p_sig.fail_condition = 'RSGT1' AND l_rows_fetched > 1) OR
        (p_sig.fail_condition = 'RS' AND l_rows_fetched > 0) OR
         (p_sig.fail_condition = 'NRS' AND l_rows_fetched = 0))) THEN
    return p_sig.fail_type;
  END IF;

  l_print_sql_out := (nvl(p_sig.print_sql_output,'Y') = 'Y' OR
					 (p_sig.print_sql_output = 'RSGT1' AND l_rows_fetched > 1) OR
                     (p_sig.print_sql_output = 'RS' AND l_rows_fetched > 0) OR
                      p_sig.child_sigs.count > 0 AND l_rows_fetched > 0);

  -- Determine signature failure status
  IF p_sig.fail_condition NOT IN ('RSGT1','RS','NRS') THEN
    -- Get the column to evaluate, if any
    l_step := '20';
    l_column := upper(substr(ltrim(p_sig.fail_condition),2,instr(p_sig.fail_condition,']') - 2));
    l_operand := rtrim(ltrim(substr(p_sig.fail_condition, instr(p_sig.fail_condition,']')+1,
      (instr(p_sig.fail_condition,'[',1,2)-instr(p_sig.fail_condition,']') - 1))));
    l_value := substr(p_sig.fail_condition, instr(p_sig.fail_condition,'[',2)+1,
      (instr(p_sig.fail_condition,']',1,2)-instr(p_sig.fail_condition,'[',1,2)-1));

    l_step := '30';
    FOR i IN 1..least(l_rows_fetched, g_max_output_rows) LOOP
      l_step := '40';
      FOR j IN 1..p_col_headings.count LOOP
        l_step := '40.1.'||to_char(j);
        l_row_fail := false;
        l_curr_col := upper(p_col_headings(j));
        l_curr_val := p_col_rows(j)(i);
        IF nvl(l_column,'&&&') = l_curr_col THEN
          l_step := '40.2.'||to_char(j);
          l_row_fail := evaluate_rowcol(l_operand, l_value, l_curr_val);
          IF l_row_fail THEN
            l_fail_flag := true;
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  -- Evaluate this signature
  l_step := '50';
  l_sig_fail := l_fail_flag OR
				(p_sig.fail_condition = 'RSGT1' AND l_rows_fetched > 1) OR
                (p_sig.fail_condition = 'RS' AND l_rows_fetched > 0) OR
                (p_sig.fail_condition = 'NRS' and l_rows_fetched = 0);

  l_step := '55';
  IF (l_sig_fail AND p_sig.include_in_xml='Y') THEN
     generate_hidden_xml(p_sig_id => p_sig_id,
                         p_sig => p_sig,
                         p_col_headings => p_col_headings,
                         p_col_rows => p_col_rows);
  END IF;

  -- If success and no print just return
  l_step := '60';
  IF ((NOT l_sig_fail) AND p_sig.print_condition IN ('FAILURE','NEVER')) THEN
    IF p_sig.fail_type = 'I' THEN
      return 'I';
    ELSE
      return 'S';
    END IF;
  ELSIF (l_sig_fail AND (p_sig.print_condition IN ('SUCCESS','NEVER'))) THEN
    return p_sig.fail_type;
  END IF;

  -- Print container div
  l_html := '<div class="divItem" id="sig'||p_sig_id||'">';

  -- Print title div
  l_step := '70';
   	g_sig_id := g_sig_id + 1;
	l_html := l_html || ' <div class="divItemTitle">' || '<a name="restable'||p_sig.title||'b"></a> <a id="restable'||to_char(g_sig_id)||'b'||'" class="detail" href="javascript:;" onclick="displayItem(this, ''restable' ||
      to_char(g_sig_id) ||''');">&#9654; '||p_sig.title||'</a>';
	
  -- Keep the counter of the parent signature to use as anchore in the table of contents
    IF (NOT l_is_child) THEN
       g_parent_sig_id := g_sig_id;
    END IF;  
	
  -- Print collapsable/expandable extra info table if there are contents
  l_step := '80';
  IF p_sig.extra_info.count > 0 OR p_sig.sig_sql is not null THEN
    g_item_id := g_item_id + 1;
    l_step := '90';
    -- Print the triangle and javascript
    l_html := l_html || '
      <a class="detailsmall" id="tbitm' || to_char(g_item_id) || 'b" href="javascript:;" onclick="displayItem(this, ''tbitm' ||
      to_char(g_item_id) ||''');"><font color="#0066CC">(Show SQL)</font></a></div>';
    -- Print the table with extra information in hidden state
    l_step := '100';
    l_html := l_html || '
      <table class="table1" id="tbitm' || to_char(g_item_id) ||
      '" style="display:none">
      <tbody><tr><th>Item Name</th><th>Item Value</th></tr>';
    -- Loop and print values
    l_step := '110';
    l_i := p_sig.extra_info.FIRST;
    WHILE l_i IS NOT NULL LOOP
      l_step := '110.1.'||l_i;
      l_html := l_html || '<tr><td>' || l_i || '</td><td>'||
        p_sig.extra_info(l_i) || '</td></tr>';
      l_step := '110.2.'||l_i;
      l_i := p_sig.extra_info.next(l_i);
    END LOOP;
    IF p_sig.sig_sql is not null THEN
      l_step := '120';
      l_html := l_html || '
         <tr><td>SQL</td><td><pre>'|| prepare_sql(p_sig.sig_sql) ||
         '</pre></td></tr>';
    END IF;
  ELSE -- no extra info or SQL to print
    l_step := '130';
    l_html := l_html || '</div>';
  END IF;

  l_step := '140';
  l_html := l_html || '</tbody></table>';

  -- Print the header SQL info table
  print_out(expand_links(l_html));
  l_html := null;

  IF l_print_sql_out THEN
    IF p_sig.child_sigs.count = 0 THEN
      -- Print the actual results table
      -- Table header
      l_step := '150';
      l_html := '<div class="divtable"><table class="table1" id="restable' || to_char(g_sig_id) ||
      '" style="display:none"><tbody>';
      -- Column headings
      l_html := l_html || '<tr>';
      l_step := '160';
      FOR i IN 1..p_col_headings.count LOOP
        l_html := l_html || '
          <th>'||nvl(p_col_headings(i),'&nbsp;')||'</th>';
      END LOOP;
      l_html := l_html || '</tr>';
      -- Print headers
      print_out(expand_links(l_html));
      -- Row values
      l_step := '170';
      FOR i IN 1..l_rows_fetched LOOP
        l_html := '<tr>';
        l_step := '170.1.'||to_char(i);
        FOR j IN 1..p_col_headings.count LOOP
          -- Evaluate if necessary
          l_step := '170.2.'||to_char(j);
          l_row_fail := false;
          l_step := '170.3.'||to_char(j);
          l_curr_col := upper(p_col_headings(j));
          l_step := '170.4.'||to_char(j);
          l_curr_val := p_col_rows(j)(i);
          l_step := '170.5.'||to_char(j);
          IF nvl(l_column,'&&&') = l_curr_col THEN
            l_step := '170.6.'||
              substr('['||l_operand||']['||l_value||']['||l_curr_val||']',1,96);
            l_row_fail := evaluate_rowcol(l_operand, l_value, l_curr_val);
          END IF;
          -- Encode blanks as HTML space if this analyzer is set so by g_preserve_trailing_blanks
          -- this ensures trailing blanks added for padding are honored by browsers
          -- affects only printing, DX summary handled separately
          IF g_preserve_trailing_blanks THEN
            l_curr_Val := RPAD(RTRIM(l_curr_Val,' '),
             -- pad length is the number of spaces existing times the length of &nbsp; => 6
            (length(l_curr_Val) - length(RTRIM(l_curr_Val,' '))) * 6 + length(RTRIM(l_curr_Val,' ')),
            '&nbsp;');
          ELSE
            l_curr_Val := RTRIM(l_curr_Val, ' ');
          END IF;
          -- Print
          l_step := '170.7.'||to_char(j);
          IF l_row_fail THEN
            l_html := l_html || '
              <td class="hlt">' || l_curr_Val || '</td>';
          ELSE
            l_html := l_html || '
              <td>' || l_curr_val || '</td>';
          END IF;
        END LOOP;
        l_html := l_html || '</tr>';
        print_out(expand_links(l_html));
      END LOOP;
	  
	l_html := '<tr><th colspan="100%"><b><i><font style="font-size:x-small; color:#333333">';
      IF p_sig.limit_rows = 'N' OR l_rows_fetched < g_max_output_rows THEN
        l_html := l_html || l_rows_fetched || ' rows selected';
      ELSE
        l_html := l_html ||'Displaying first '||to_char(g_max_output_rows);
      END IF;
      l_html := l_html ||' - Elapsed time: ' || format_elapsed(g_query_elapsed) || '
        </font></i></b><br>';
	  l_html := l_html || '</th></tr>';
      print_out(l_html);

      -- End of results and footer
      l_step := '180';
      l_html :=  '</tbody></table></div>';
      l_step := '190';
      print_out(l_html);
--
    ELSE -- there are children signatures
      -- Print master rows and call appropriate processes for the children
      -- Table header
      l_html := '<div class="divtable"><table class="table1" id="restable' || to_char(g_sig_id) ||
      '" style="display:none"><tbody>';
      -- Row values
      l_step := '200';
      FOR i IN 1..l_rows_fetched LOOP
        l_step := '200.1.'||to_char(i);
        -- Column headings printed for each row
        l_html := l_html || '<tr>';
        FOR j IN 1..p_col_headings.count LOOP
          l_step := '200.2.'||to_char(j);
          IF upper(nvl(p_col_headings(j),'XXX')) not like '##$$FK_$$##' THEN
            l_html := l_html || '
              <th class="master">'||nvl(p_col_headings(j),'&nbsp;')||'</th>';
          END IF;
        END LOOP;
        l_step := '200.3';
        l_html := l_html || '</tr>';
        -- Print headers
        print_out(expand_links(l_html));
        -- Print a row
        l_html := '<tr class="master">';

        l_printing_cols := 0;
        FOR j IN 1..p_col_headings.count LOOP
          l_step := '200.4.'||to_char(j);

          l_curr_col := upper(p_col_headings(j));
          l_curr_val := p_col_rows(j)(i);

          -- If the col is a FK set the global replacement vals
          IF l_curr_col like '##$$FK_$$##' THEN
            l_step := '200.5';
            g_sql_tokens(l_curr_col) := l_curr_val;
          ELSE -- printable column
            l_printing_cols := l_printing_cols + 1;
            -- Evaluate if necessary
            l_row_fail := false;
            IF nvl(l_column,'&&&') = l_curr_col THEN
              l_step := '200.6'||
                substr('['||l_operand||']['||l_value||']['||l_curr_val||']',1,96);
              l_row_fail := evaluate_rowcol(l_operand, l_value, l_curr_val);
            END IF;
            -- Encode blanks as HTML space if this analyzer is set so by g_preserve_trailing_blanks
            -- this ensures trailing blanks added for padding are honored by browsers
            -- affects only printing, DX summary handled separately
            IF g_preserve_trailing_blanks THEN
              l_curr_Val := RPAD(RTRIM(l_curr_Val,' '),
               -- pad length is the number of spaces existing times the length of &nbsp; => 6
              (length(l_curr_Val) - length(RTRIM(l_curr_Val,' '))) * 6 + length(RTRIM(l_curr_Val,' ')),
              '&nbsp;');
            ELSE
              l_curr_Val := RTRIM(l_curr_Val, ' ');
            END IF;
            -- Print
            IF l_row_fail THEN
              l_html := l_html || '
                <td class="hlt">' || l_curr_Val || '</td>';
            ELSE
              l_html := l_html || '
                <td>' || l_curr_val || '</td>';
            END IF;
          END IF;
        END LOOP;
        l_html := l_html || '</tr>';
        print_out(expand_links(l_html));
-- AGL KLUGE FOR VERIFY AUTHORITY REMOVE IN TEMPLATES
        IF p_sig_id IN ('APP_SUP_HIERARCHY_MAIN','APP_POS_HIERARCHY_MAIN') THEN
          verify_approver(to_number(g_sql_tokens('##$$FK1$$##')));
        END IF;
-- END AGL KLUGE

        l_html := null;
        FOR i IN p_sig.child_sigs.first..p_sig.child_sigs.last LOOP
          print_out('<tr><td colspan="'||to_char(l_printing_cols)||
            '"><blockquote>');
          DECLARE
            l_col_rows  COL_LIST_TBL := col_list_tbl();
            l_col_hea   VARCHAR_TBL := varchar_tbl();
            l_child_sig SIGNATURE_REC;
            l_result    VARCHAR2(1);
          BEGIN
           l_child_sig := g_signatures(p_sig.child_sigs(i));
           print_log('Processing child signature: '||p_sig.child_sigs(i));
           run_sig_sql(l_child_sig.sig_sql, l_col_rows, l_col_hea,
             l_child_sig.limit_rows);
           l_result := process_signature_results(p_sig.child_sigs(i),
             l_child_sig, l_col_rows, l_col_hea, TRUE);
           set_item_result(l_result);

          IF l_result in ('W','E') THEN
              l_fail_flag := true;
            IF l_result = 'E' THEN
              l_error_type := 'E';
            ELSIF (l_result = 'W') AND ((l_error_type is NULL) OR (l_error_type != 'E')) THEN
              l_error_type := 'W';
            END IF;
            g_family_result := l_error_type;
          END IF; 

          EXCEPTION WHEN OTHERS THEN
            print_log('Error processing child signature: '||p_sig.child_sigs(i));
            print_log('Error: '||sqlerrm);
            raise;
          END;

          print_out('</blockquote></td></tr>');
        END LOOP;
      END LOOP;
      
      --l_sig_fail := (l_sig_fail OR l_fail_flag);

      -- End of results and footer
      l_step := '210';
      l_html :=  '</tbody></table></div>
        <font style="font-size:x-small; color:#333333">';
      l_step := '220';
      IF p_sig.limit_rows = 'N' OR l_rows_fetched < g_max_output_rows THEN
        l_html := l_html || l_rows_fetched || ' rows selected';
      ELSE
        l_html := l_html ||'Displaying first '||to_char(g_max_output_rows);
      END IF;
      l_html := l_html ||' - Elapsed time: ' || format_elapsed(g_query_elapsed) || '
        </font><br>';
      print_out(l_html);
    END IF; -- master or child
  END IF; -- print output is true

  -- Print actions
  IF l_sig_fail THEN
    l_step := '230';

    IF p_sig.fail_type = 'E' THEN 
      l_html := '<div class="divuar"><span class="divuar1"><img class="error_ico"> Error:</span>' ||
        p_sig.problem_descr;
    ELSIF p_sig.fail_type = 'W' THEN
      l_html := '<div class="divwarn"><span class="divwarn1"><img class="warn_ico"> Warning:</span>' ||
        p_sig.problem_descr;
    ELSE
      l_html := '<div class="divok"><span class="divok1">Information:</span>' ||
        p_sig.problem_descr;
    END IF;


    -- Print solution only if passed
    l_step := '240';
    IF p_sig.solution is not null THEN
      l_html := l_html || '
        <br><br><span class="solution">Findings and Recommendations:</span><br>
        ' || p_sig.solution;
    END IF;

    -- Close div here cause success div is conditional
    l_html := l_html || '</div>';
  ELSE
    l_step := '250';
    IF p_sig.success_msg is not null THEN
      IF p_sig.fail_type = 'I' THEN
        l_html := '
          <br><div class="divok"><div class="divok1">Information:</div>'||
          nvl(p_sig.success_msg, 'No instances of this problem found') ||
          '</div>';
      ELSE
        l_html := '
          <br><div class="divok"><div class="divok1"><img class="check_ico"> All checks passed.</div>'||
          nvl(p_sig.success_msg,
          'No instances of this problem found') ||
          '</div>';
      END IF;
    ELSE
      l_html := null;
    END IF;
  END IF;

  IF p_sig.child_sigs.count > 0 and NOT (l_is_child) THEN
    IF g_family_result = 'E' THEN 
       l_html := l_html || '
         <div class="divuar"><div class="divuar1"><img class="error_ico"> Error:</div> There was an error reported in one of the child checks. Please expand the section for more information.</div>';	
    ELSIF g_family_result = 'W' THEN
       l_html := l_html || '
         <div class="divwarn"><div class="divwarn1"><img class="warn_ico"> Warning:</div> There was an issue reported in one of the child checks. Please expand the section for more information.</div>';	
    END IF;     
  END IF;  
  
  -- Add final tags
  l_html := l_html || '
    </div>' || '<br><font style="font-size:x-small;">
    <a href="#top"><font color="#0066CC">Back to top</font></a></font><br>' || '<br>';
	 
   --Code for Table of Contents of each section  
   g_section_sig := g_section_sig + 1;
   sig_count := g_section_sig;  
   
   IF NOT (l_is_child) THEN
     -- for even # signatures
   g_parent_sig_count := g_parent_sig_count + 1;
   IF MOD(g_parent_sig_count, 2) = 0 THEN

   -- link to the parent sections only
   g_section_toc := g_section_toc || '<td>' || '<a href="#restable'||to_char(g_parent_sig_id)||'b">'||p_sig.title||'</a> ';

   IF ((l_sig_fail) AND (p_sig.fail_type ='E' OR l_error_type = 'E')) OR (g_family_result = 'E') THEN 
     g_section_toc := g_section_toc || '<img class="error_ico">';       
   ELSIF ((l_sig_fail) AND (p_sig.fail_type ='W' OR l_error_type = 'W')) OR (g_family_result = 'W') THEN 
     g_section_toc := g_section_toc ||'<img class="warn_ico">';   	 
   END IF;  
           
   g_section_toc := g_section_toc || '</td></tr>';
   
   ELSE
   -- for odd # signatures start the row
   -- link to the parent sections only
   g_section_toc := g_section_toc || '<tr class="toctable"><td>' || '<a href="#restable'||to_char(g_parent_sig_id)||'b">'||p_sig.title||'</a> ';
   
   IF ((l_sig_fail) AND (p_sig.fail_type ='E' OR l_error_type = 'E')) OR (g_family_result = 'E') THEN 
     g_section_toc := g_section_toc || '<img class="error_ico">';       
   ELSIF ((l_sig_fail) AND (p_sig.fail_type ='W' OR l_error_type = 'W')) OR (g_family_result = 'W') THEN 
     g_section_toc := g_section_toc ||'<img class="warn_ico">';   	 
   END IF;  

       
   g_section_toc := g_section_toc || '</td>';   
    
	END IF;

  END IF;
   
	 
  -- Increment the print count for the section	   
  l_step := '260';
  g_sections(g_sections.last).print_count :=
       g_sections(g_sections.last).print_count + 1;

  -- Print
  l_step := '270';
  print_out(expand_links(l_html));
   
	 
  IF l_sig_fail THEN
    l_step := '280';
    return p_sig.fail_type;
  ELSE
    l_step := '290';
    IF p_sig.fail_type = 'I' THEN
      return 'I';
    ELSE
      return 'S';
    END IF;
  END IF;
  

  
EXCEPTION
  WHEN L_INV_PARAM THEN
    print_log('Invalid parameter error in process_signature_results at step '
      ||l_step);
    raise;
  WHEN OTHERS THEN
    print_log('Error in process_signature_results at step '||l_step);
    g_errbuf := l_step;
    raise;
END process_signature_results;

----------------------------------------------------------------
-- Creates a report section                                   --
-- For now it just prints html, in future it could be         --
-- smarter by having the definition of the section logic,     --
-- signatures etc....                                         --
----------------------------------------------------------------

PROCEDURE start_section(p_sect_title varchar2) is
  lsect section_rec;
  
BEGIN
  lsect.name := p_sect_title;
  lsect.result := 'U'; -- 'U' stands for undefined which is a temporary status
  lsect.error_count := 0;
  lsect.warn_count := 0;
  lsect.success_count := 0;
  lsect.print_count := 0;
  g_sections(g_sections.count + 1) := lsect;
  g_section_toc := null;
  g_section_sig := 0;
  sig_count := null;
  g_parent_sig_count := 0;  
  
  -- Print section header
  print_out('
  <div id="page'||g_sect_no|| '" style="display: none;">');
  print_out('
<div class="divSection">
<div class="divSectionTitle" id="sect' || g_sections.last || '">
<div class="left"  id="sect_title' || g_sections.last || '" font style="font-weight: bold; font-size: x-large;" align="left" color="#FFFFFF">' || p_sect_title || ': 
</font> 
</div>
       <div class="right" font style="font-weight: normal; font-size: small;" align="right" color="#FFFFFF"> 
          <a class="detail" onclick="openall();" href="javascript:;">
          <font color="#FFFFFF">&#9654; Expand All Checks</font></a> 
          <font color="#FFFFFF">&nbsp;/ &nbsp; </font><a class="detail" onclick="closeall();" href="javascript:;">
          <font color="#FFFFFF">&#9660; Collapse All Checks</font></a> 
       </div>
  <div class="clear"></div>
</div><br>');	

  -- Table of Content DIV
  -- Making DIV invisible by default as later has logic to show TOC only if have 2+ signatures
   print_out('<div class="divItem" style="display: none" id="toccontent'|| g_sections.last||'"></div><br>');
  -- end of TOC DIV		
    		
    print_out('<div id="' || g_sections.last ||'contents">');

-- increment section #
  g_sect_no:=g_sect_no+1;

END start_section;


----------------------------------------------------------------
-- Finalizes a report section                                 --
-- Finalizes the html                                         --
----------------------------------------------------------------

PROCEDURE end_section (
  p_success_msg IN VARCHAR2 DEFAULT 'All checks passed.') IS
  
  l_loop_count NUMBER;
  
BEGIN
  IF g_sections(g_sections.last).result = 'S' AND
     g_sections(g_sections.last).print_count = 0 THEN
    print_out('<div class="divok">'||p_success_msg||'</div>');
  END IF;
  print_out('</div></div><br><font style="font-size:x-small;">
    <a href="#top"><font color="#0066CC">Back to top</font></a></font><br><br>');
   print_out('</div>');
   
 -- Printing table for Table of Content and contents
 -- IF is to print end tag of table row for odd number of sigs
	 
	 IF SUBSTR (g_section_toc, length(g_section_toc)-5, 5) != '</tr>'
		THEN g_section_toc := g_section_toc || '</tr>';
		
	 end if;	
	 
	 g_section_toc := '<table class="toctable" border="0" width="90%" align="center" cellspacing="0" cellpadding="0">' || g_section_toc || '</table>';
	 
 -- Printing 'In This Section' only have 2 or more signatures
	 IF sig_count > 1
	    THEN
	   print_out('
		<script type="text/javascript">
		var a=document.getElementById("toccontent'|| g_sections.last||'");
		a.style.display = "block";
		  a.innerHTML = ''' || '<div class="divItemTitle">In This Section</div>' || g_section_toc ||'''; </script> ');
	end if;	  
 
END end_section;

----------------------------------------------------------------
-- Creates a report sub section                               --
-- workaround for now in future normal sections should        --
-- support nesting                                            --
----------------------------------------------------------------

PROCEDURE print_rep_subsection(p_sect_title varchar2) is
BEGIN
  print_out('<div class="divSubSection"><div class="divSubSectionTitle">' ||
    p_sect_title || '</div><br>');
END print_rep_subsection;

PROCEDURE print_rep_subsection_end is
BEGIN
  print_out('</div<br>');
END print_rep_subsection_end;


-------------------------
-- Recommended patches 
-------------------------
-- PSD #4
FUNCTION check_rec_patches RETURN VARCHAR2 IS

  l_col_rows   COL_LIST_TBL := col_list_tbl(); -- Row values
  l_hdr        VARCHAR_TBL := varchar_tbl(); -- Column headings
  l_app_date   DATE;         -- Patch applied date
  l_extra_info HASH_TBL_4K;   -- Extra information
  l_step       VARCHAR2(10);
  l_sig        SIGNATURE_REC;
  l_rel       VARCHAR2(3);

  CURSOR get_app_date(p_ptch VARCHAR2, p_rel VARCHAR2) IS			  
   SELECT Max(Last_Update_Date) as date_applied
    FROM Ad_Bugs Adb 
    WHERE Adb.Bug_Number like p_ptch
    AND ad_patch.is_patch_applied(p_rel, -1, adb.bug_number)!='NOT_APPLIED';
    
BEGIN
  -- Column headings
  l_step := '10';
  l_hdr.extend(5);
  l_hdr(1) := 'Patch';
  l_hdr(2) := 'Applied';
  l_hdr(3) := 'Date';
  l_hdr(4) := 'Name';
  l_hdr(5) := 'Note';

  -- PSD #4a
  -- Row col values is release dependent
     -- Last parameter (4 in this case) matches number of characters of the Apps Version (12.0)
     -- So if checking for '11.5.10.2' then parameter will need to be 9
	     -- ie: IF substr(g_rep_info('Apps Version'),1,9) = '11.5.10.2'
  IF substr(g_rep_info('Apps Version'),1,4) = '12.0' THEN
        l_rel := 'R12';
        l_step := '20';
        l_col_rows.extend(5);
        l_col_rows(1)(1) := '8781255';
        l_col_rows(2)(1) := 'No';
        l_col_rows(3)(1) := NULL;
        l_col_rows(4)(1) := 'Update Aug 2009 (12.0.x)';
        l_col_rows(5)(1) := '[1122052.1]';
        l_col_rows(1)(2) := '12330727';
        l_col_rows(2)(2) := 'No';
        l_col_rows(3)(2) := NULL;
        l_col_rows(4)(2) := 'PO Output for communication '||
                     'always terminates in error in debug mode';
        l_col_rows(5)(2) := '[1122052.1]';
        l_col_rows(1)(3) := '12360278';
        l_col_rows(2)(3) := 'No';
        l_col_rows(3)(3) := NULL;
        l_col_rows(4)(3) := 'After patch 9593873, Note '||
                     'entered in Response section of notification was not '||
                     'getting updated in action history when document was rejected';
        l_col_rows(5)(3) := '[1122052.1]';
        l_col_rows(1)(4) := '12590430';
        l_col_rows(2)(4) := 'No';
        l_col_rows(3)(4) := NULL;
        l_col_rows(4)(4) := 'Patch to clean up the regression issue in poxwfpoa.wft';
        l_col_rows(5)(4) := '[1122052.1]';
    
  ELSE IF substr(g_rep_info('Apps Version'),1,4) = '12.1' THEN
        l_rel := 'R12';
        l_step := '30';
        l_col_rows.extend(6);
       
        l_col_rows(1)(1) := '9868639';
        l_col_rows(2)(1) := 'No';
        l_col_rows(3)(1) := NULL;
        l_col_rows(4)(1) := 'java.net.MalformedURLException while sending OA framework '||
                     'notifications from regions like "Approve Requisition '||
                     'Notification (Simplified).';
        l_col_rows(5)(1) := '[1107017.1]';
       
        l_col_rows(1)(2) := '12923944';
        l_col_rows(2)(2) := 'No';
        l_col_rows(3)(2) := NULL;
        l_col_rows(4)(2) := 'After upgrading to 12.1.3 the PO Document '||
                     'Approval Manager (POXCON) dies immediately after '||
                     'starting it up.';
        l_col_rows(5)(2) := '[1413393.1]';
       
        l_col_rows(1)(3) := '11063775';
        l_col_rows(2)(3) := 'No';
        l_col_rows(3)(3) := NULL;
        l_col_rows(4)(3) := 'Patches to prevent error FRM-40654: '||
                     '"Record has been updated." error when updating a PO '||
                     'or Requisition';
        l_col_rows(5)(3) := '[1325536.1]';
       
        l_col_rows(1)(4) := '13495209';
        l_col_rows(2)(4) := 'No';
        l_col_rows(3)(4) := NULL;
        l_col_rows(4)(4) := 'Accrual Reconciliation Load Run Program '||
                     'Cannot Migrate Write Off Transactions from 11i to R12: '||
                     'errors with ORA-00001: unique constraint '||
                     '(BOM.CST_WRITE_OFFS_U1) violated.';
        l_col_rows(5)(4) := '[1475396.1]';
       
        l_col_rows(1)(5) := '12677981';
        l_col_rows(2)(5) := 'No';
        l_col_rows(3)(5) := NULL;
        l_col_rows(4)(5) := 'Unable Approve a Purchase Order Due to Tax '||
                     'Error Exception: 023 - An unexpected error has occurred.';
        l_col_rows(5)(5) := '[1281362.1]';
                           
        l_col_rows(1)(6) := '21198991';
        l_col_rows(2)(6) := 'No';
        l_col_rows(3)(6) := NULL;
        l_col_rows(4)(6) := 'Oracle Procurement Rollup patch (March 2015)';
        l_col_rows(5)(6) := '[1468883.1]';
    
    ELSE -- R12.2
        l_step := '35';
        l_col_rows.extend(5);
    
        l_col_rows(1)(1) := '17947999';
        l_col_rows(2)(1) := 'No';
        l_col_rows(3)(1) := NULL;
        l_col_rows(4)(1) := 'Release 12.2.3 - provides R12.PRC_PF.B.delta.4';
        l_col_rows(5)(1) := '[222339.1]';
        
        l_col_rows(1)(2) := '17919161';
        l_col_rows(2)(2) := 'No';
        l_col_rows(3)(2) := NULL;
        l_col_rows(4)(2) := '12.2.4 -ORACLE E-BUSINESS SUITE 12.2.4 RELEASE UPDATE PACK';
        l_col_rows(5)(2) := '[1617458.1]';
    
    END IF;  
  END IF;

  -- Check if applied
  IF l_col_rows.exists(1) THEN
     FOR i in 1..l_col_rows(1).count loop
       l_step := '40';
       OPEN get_app_date(l_col_rows(1)(i),l_rel);
       FETCH get_app_date INTO l_app_date;
       CLOSE get_app_date;
       IF l_app_date is not null THEN
         l_step := '50';
         l_col_rows(2)(i) := 'Yes';
         l_col_rows(3)(i) := to_char(l_app_date);
       END IF;
     END LOOP;
   END IF;  

  --Render
  l_step := '60';

  l_sig.title := 'Recommended Patches';
  l_sig.fail_condition := '[Applied] = [No]';
  l_sig.problem_descr := 'Some recommended patches are not applied '||
    'in this instance';
  l_sig.solution := '<ul><li>Please review list above and schedule
    to apply these patches as soon as possible</li>
    <li>Refer to the note indicated for more information about
    each patch</li></ul>';
  l_sig.success_msg := null;
  l_sig.print_condition := 'ALWAYS';
  l_sig.fail_type := 'W';
  l_sig.print_sql_output := 'Y';
  l_sig.limit_rows := 'N';  
  l_sig.include_in_xml :='Y';

  l_step := '70';
  RETURN process_signature_results(
    'REC_PATCH_CHECK',     -- sig ID
    l_sig,                 -- signature information
    l_col_rows,            -- data
    l_hdr);                -- headers
EXCEPTION WHEN OTHERS THEN
  print_log('Error in check_rec_patches at step '||l_step);
  raise;
END check_rec_patches;

---------------------------------
-- Get AME Approvers List
---------------------------------

FUNCTION get_ame_approvers RETURN VARCHAR2 IS

  l_col_rows   COL_LIST_TBL := col_list_tbl(); -- Row values
  l_hdr        VARCHAR_TBL := varchar_tbl(); -- Column headings
  l_app_date   DATE;         -- Patch applied date
  l_extra_info HASH_TBL_4K;   -- Extra information
  l_step       VARCHAR2(10);
  l_sig        SIGNATURE_REC;
  l_approvers  AME_UTIL.APPROVERSTABLE2;
  l_complete   VARCHAR2(10);

BEGIN
  -- Column headings
  l_step := '10';
  l_hdr.extend(13);
  l_hdr(1) := 'Num';
  l_hdr(2) := 'Name';
  l_hdr(3) := 'Appr Ord#';
  l_hdr(4) := 'Member Ord#';
  l_hdr(5) := 'Item Class';
  l_hdr(6) := 'Item ID';
  l_hdr(7) := 'Auth';
  l_hdr(8) := 'Act Type ID';
  l_hdr(9) := 'Grp or Chain ID';
  l_hdr(10) := 'Appr Status';
  l_hdr(11) := 'Appr Cat';
  l_hdr(12) := 'Occur';
  l_hdr(13) := 'API Ins';

  l_step := '20';
  BEGIN
    ame_api2.getAllApprovers7(
      applicationIdIn => 201,
      transactionTypeIn => g_sql_tokens('##$$AMETRXTP$$##'),
      transactionIdIn => g_sql_tokens('##$$AMETRXID$$##'),
      approvalProcessCompleteYNOut => l_complete, 
      approversOut => l_approvers);
  EXCEPTION WHEN OTHERS THEN
-- AGL Temporary workaround for failure of the procedure for POs
    l_sig.problem_descr := sqlerrm;
  END;

  l_step := '30';
  l_col_rows.extend(13);
  FOR i in 1 .. l_approvers.count LOOP
    l_step := '30.1';
    l_col_rows(1)(i) := to_char(i);
    l_col_rows(2)(i) := l_approvers(i).name;
    l_col_rows(3)(i) := l_approvers(i).approver_order_number;
    l_col_rows(4)(i) := l_approvers(i).member_order_number;
    l_col_rows(5)(i) := l_approvers(i).item_class;
    l_col_rows(6)(i) := l_approvers(i).item_id;
    l_col_rows(7)(i) := l_approvers(i).authority;
    l_col_rows(8)(i) := to_char(l_approvers(i).action_type_id);
    l_col_rows(9)(i) := to_char(l_approvers(i).group_or_chain_id);
    l_col_rows(10)(i) := l_approvers(i).approval_status;
    l_col_rows(11)(i) := l_approvers(i).approver_category;
    l_col_rows(12)(i) := to_char(l_approvers(i).occurrence);
    l_col_rows(13)(i) := l_approvers(i).api_insertion;
  END LOOP;

  --Render
  l_step := '40';

  l_sig.title := 'AME Approvers List';
  l_sig.fail_condition := 'NRS';
-- AGL Temporary workaround for failure of the procedure for POs
  l_sig.problem_descr := 'No approvers found. '||l_sig.problem_descr;
  l_sig.solution := 'Review the AME configuration information to determine
    why there are no approvers.';
  l_sig.success_msg := 'Approval Complete: '||l_complete;
  l_sig.print_condition := 'ALWAYS';
  l_sig.fail_type := 'E';
  l_sig.print_sql_output := 'RS';
  l_sig.limit_rows := 'N';

  l_step := '50';
  RETURN process_signature_results(
    'AME_APPROVER_LIST',   -- sig ID
    l_sig,                 -- signature information
    l_col_rows,            -- data
    l_hdr);                -- headers
EXCEPTION WHEN OTHERS THEN
  print_log('Error in get_ame_approvers at step '||l_step);
  raise;
END get_ame_approvers;


---------------------------------
-- Get list of AME rules
---------------------------------
FUNCTION get_ame_rules_for_trxn(p_trxn_id VARCHAR2) RETURN VARCHAR2 IS

   l_col_rows   COL_LIST_TBL := col_list_tbl(); -- Row values
   l_hdr        VARCHAR_TBL := varchar_tbl(); -- Column headings

   l_sig        SIGNATURE_REC;
   l_ame_rules  ame_rules_list;
   l_error      VARCHAR2(100);
   l_step       VARCHAR2(10);
   
BEGIN

   -- Column headings
   l_step := '10';
   l_hdr.extend(12);
   l_hdr(1) := 'Rule ID';
   l_hdr(2) := 'Name';
   l_hdr(3) := 'Item Class ID';
   l_hdr(4) := 'Item Class';
   l_hdr(5) := 'Item ID';
   l_hdr(6) := 'Rule Type';
   l_hdr(7) := 'Rule Type ID';
   l_hdr(8) := 'Category';
   l_hdr(9) := 'Usage Start Date';
   l_hdr(10) := 'Usage End Date';
   l_hdr(11) := 'Conditions List';
   l_hdr(12) := 'Actions List';
   
   l_step := '20';
   BEGIN
       ame_test_utility_pkg.getApplicableRules( 
            applicationIdIn    => to_number(g_sql_tokens('##$$AMEAPPID$$##')),
            transactionIdIn    => p_trxn_id,
            isRealTransaction  => 'Y',
            processPriorities  => 'Y',
            rulesOut           => l_ame_rules,
            errString          => l_error);
   EXCEPTION WHEN OTHERS THEN
       l_sig.problem_descr := l_error;
   END;

   l_step := '30';
   l_col_rows.extend(12); 

   IF l_ame_rules.COUNT > 0 THEN
       FOR i IN l_ame_rules.FIRST .. l_ame_rules.LAST
       LOOP
           print_log(l_ame_rules(i).name);
           l_step := '30.1';
           l_col_rows(1)(i) := l_ame_rules(i).rule_id;        
           l_col_rows(2)(i) := l_ame_rules(i).name;           
           l_col_rows(3)(i) := l_ame_rules(i).item_class_id;  
           l_col_rows(4)(i) := l_ame_rules(i).item_class;     
           l_col_rows(5)(i) := l_ame_rules(i).item_id;        
           l_col_rows(6)(i) := l_ame_rules(i).rule_type;      
           l_col_rows(7)(i) := l_ame_rules(i).rule_type_id;   
           l_col_rows(8)(i) := l_ame_rules(i).category;       
           l_col_rows(9)(i) := l_ame_rules(i).usageStartDate; 
           l_col_rows(10)(i) := l_ame_rules(i).usageEndDate;   
           l_col_rows(11)(i) := l_ame_rules(i).conditionsList; 
           l_col_rows(12)(i) := l_ame_rules(i).actionsList;    
        END LOOP;
    ELSE 
        print_log('get_ame_rules_for_trxn: No rules found!');    
    END IF; 
    
    l_sig.title := 'AME Test Workbench Output - Rules for transaction ' || p_trxn_id;
    l_sig.fail_condition := 'NRS';
    l_sig.problem_descr := 'No rules found. '||l_sig.problem_descr;
    l_sig.solution := 'Review the AME configuration information to determine why there are no available rules.';
    l_sig.success_msg := '';
    l_sig.print_condition := 'ALWAYS';
    l_sig.fail_type := 'I';
    l_sig.print_sql_output := 'RS';
    l_sig.limit_rows := 'N';
    
    RETURN process_signature_results(
      'AME_RULES_TRXN',      -- sig ID
      l_sig,                 -- signature information
      l_col_rows,            -- data
      l_hdr);                -- headers    
        
EXCEPTION WHEN OTHERS THEN
   print_log ('Exception in get_ame_rules_for_trxn at step '||l_step); 
END get_ame_rules_for_trxn;


---------------------------------------------------------
-- Get list of AME approvers for a specific transaction -
---------------------------------------------------------
FUNCTION get_ame_approvers_for_trxn(p_trxn_id VARCHAR2) RETURN VARCHAR2 IS

   l_col_rows       COL_LIST_TBL := col_list_tbl(); -- Row values
   l_hdr            VARCHAR_TBL := varchar_tbl(); -- Column headings

   l_sig            SIGNATURE_REC;
   l_ame_approvers  ame_approvers_list;
   l_error          VARCHAR2(100);
   l_step           VARCHAR2(10);
   
BEGIN

   -- Column headings
   l_step := '10';
   l_hdr.extend(13);
   l_hdr(1) := 'Approver Order Number';
   l_hdr(2) := 'Approver Type';
   l_hdr(3) := 'Approver';
   l_hdr(4) := 'Category';
   l_hdr(5) := 'Item Class';
   l_hdr(6) := 'Item ID';
   l_hdr(7) := 'Chain Number';
   l_hdr(8) := 'Sub List';
   l_hdr(9) := 'Action Type';
   l_hdr(10) := 'Source';
   l_hdr(11) := 'Source Rules';
   l_hdr(12) := 'Productions';
   l_hdr(13) := 'Status';
   
   l_step := '20';
      
   BEGIN
       ame_test_utility_pkg.getApprovers( 
           applicationIdIn     => to_number(g_sql_tokens('##$$AMEAPPID$$##')),
           transactionIdIn     => p_trxn_id,
           isRealTransaction   => 'Y',
           approverListStageIn => 6,
           approversOut        => l_ame_approvers,
           errString           => l_error); 
   EXCEPTION WHEN OTHERS THEN
       l_sig.problem_descr := l_error;
   END;

   l_step := '30';
   l_col_rows.extend(13); 

   IF l_ame_approvers.COUNT > 0 THEN
       FOR i IN l_ame_approvers.FIRST .. l_ame_approvers.LAST
       LOOP
           print_log(l_ame_approvers(i).name);
           l_step := '30.1';
           
           l_col_rows(1)(i) := l_ame_approvers(i).approver_order_number     ;
           l_col_rows(2)(i) := l_ame_approvers(i).orig_system_name          ;
           l_col_rows(3)(i) := l_ame_approvers(i).group_name                ;
           l_col_rows(4)(i) := l_ame_approvers(i).approver_category_desc    ;
           l_col_rows(5)(i) := l_ame_approvers(i).item_class                ;
           l_col_rows(6)(i) := l_ame_approvers(i).item_id                   ;
           l_col_rows(7)(i) := l_ame_approvers(i).group_or_chain_id         ;
           l_col_rows(8)(i) := l_ame_approvers(i).authority_desc            ;
           l_col_rows(9)(i) := l_ame_approvers(i).action_type_name          ;
           l_col_rows(10)(i) := l_ame_approvers(i).source                    ;
           l_col_rows(11)(i) := l_ame_approvers(i).source_Desc               ;
           l_col_rows(12)(i) := l_ame_approvers(i).productionsList           ; 
           l_col_rows(13)(i) := l_ame_approvers(i).productionsList           ; 
           
        END LOOP;
    ELSE 
        print_log('get_ame_approvers_for_trxn: No rules found!');    
    END IF; 
    l_sig.title := 'AME Test Workbench Output - Approvers for transaction ' || p_trxn_id;
    l_sig.fail_condition := 'NRS';
    l_sig.problem_descr := 'No approvers found. '||l_sig.problem_descr;
    l_sig.solution := 'Review the AME configuration information to determine why there are no approvers.';
    l_sig.success_msg := '';
    l_sig.print_condition := 'ALWAYS';
    l_sig.fail_type := 'I';
    l_sig.print_sql_output := 'RS';
    l_sig.limit_rows := 'N';
    
    RETURN process_signature_results(
      'AME_APPROVERS_TRXN',  -- sig ID
      l_sig,                 -- signature information
      l_col_rows,            -- data
      l_hdr);                -- headers  
      
EXCEPTION WHEN OTHERS THEN
   print_log ('Exception in get_ame_approvers_for_trxn at step '||l_step); 
END get_ame_approvers_for_trxn;



PROCEDURE add_signature(
  p_sig_id           VARCHAR2,     -- Unique Signature identifier
  p_sig_sql          VARCHAR2,     -- The text of the signature query
  p_title            VARCHAR2,     -- Signature title
  p_fail_condition   VARCHAR2,     -- RSGT1 (RS greater than 1), RS (row selected), NRS (no row selected)
  p_problem_descr    VARCHAR2,     -- Problem description
  p_solution         VARCHAR2,     -- Problem solution
  p_success_msg      VARCHAR2    DEFAULT null,      -- Message on success
  p_print_condition  VARCHAR2    DEFAULT 'ALWAYS',  -- ALWAYS, SUCCESS, FAILURE, NEVER
  p_fail_type        VARCHAR2    DEFAULT 'W',       -- Warning(W), Error(E), Informational(I) is for use of data dump so no validation
  p_print_sql_output VARCHAR2    DEFAULT 'RS',      -- Y/N/RS - when to print data
  p_limit_rows       VARCHAR2    DEFAULT 'Y',       -- Y/N
  p_extra_info       HASH_TBL_4K DEFAULT CAST(null AS HASH_TBL_4K), -- Additional info
  p_child_sigs       VARCHAR_TBL DEFAULT VARCHAR_TBL(),
  p_include_in_dx_summary   VARCHAR2    DEFAULT 'N') --should signature be included in DX Summary
 IS

  l_rec signature_rec;
BEGIN
  l_rec.sig_sql          := p_sig_sql;
  l_rec.title            := p_title;
  l_rec.fail_condition   := p_fail_condition;
  l_rec.problem_descr    := p_problem_descr;
  l_rec.solution         := p_solution;
  l_rec.success_msg      := p_success_msg;
  l_rec.print_condition  := p_print_condition;
  l_rec.fail_type        := p_fail_type;
  l_rec.print_sql_output := p_print_sql_output;
  l_rec.limit_rows       := p_limit_rows;
  l_rec.extra_info       := p_extra_info;
  l_rec.child_sigs       := p_child_sigs;
  l_rec.include_in_xml   := p_include_in_dx_summary;
  g_signatures(p_sig_id) := l_rec;
EXCEPTION WHEN OTHERS THEN
  print_log('Error in add_signature procedure: '||p_sig_id);
  raise;
END add_signature;


FUNCTION run_stored_sig(p_sig_id varchar2) RETURN VARCHAR2 IS

  l_col_rows COL_LIST_TBL := col_list_tbl();
  l_col_hea  VARCHAR_TBL := varchar_tbl();
  l_sig      signature_rec;
  l_key      VARCHAR2(255);  

BEGIN
  print_log('Processing signature: '||p_sig_id);
  -- Get the signature record from the signature table
  BEGIN
    l_sig := g_signatures(p_sig_id);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    print_log('No such signature '||p_sig_id||' error in run_stored_sig');

    raise;
  END;

  -- Clear FK values if the sig has children
  IF l_sig.child_sigs.count > 0 THEN
    l_key := g_sql_tokens.first;
    WHILE l_key is not null LOOP
      IF l_key like '##$$FK_$$##' THEN 
        g_sql_tokens.delete(l_key);
      END IF;
      l_key := g_sql_tokens.next(l_key);
    END LOOP;
  END IF;
  
  -- Run SQL
  run_sig_sql(l_sig.sig_sql, l_col_rows, l_col_hea,
              l_sig.limit_rows);

  -- Evaluate and print
  RETURN process_signature_results(
       p_sig_id,               -- signature id
       l_sig,                  -- Name/title of signature item
       l_col_rows,             -- signature SQL row values
       l_col_hea);             -- signature SQL column names
 
	   
EXCEPTION WHEN OTHERS THEN
  print_log('Error in run_stored_sig procedure for sig_id: '||p_sig_id);
  print_log('Error: '||sqlerrm);
  print_error('PROGRAM ERROR<br/>
    Error for sig '||p_sig_id||' '||sqlerrm||'<br/>
    See the log file for additional details');
  return null;
END run_stored_sig;


--########################################################################################
--                PO APPROVAL ANALYZER SPECIFICS FOLLOW
--########################################################################################

----------------------------------------------------------------
--- Validate Parameters                                      ---
----------------------------------------------------------------
-- PSD #5
PROCEDURE validate_parameters (
  p_mode            IN VARCHAR2,  
  p_org_id          IN NUMBER,
  p_trx_type        IN VARCHAR2,
  p_trx_num         IN VARCHAR2,
  p_release_num     IN NUMBER,
  p_include_wf      IN VARCHAR2,
  p_from_date       IN DATE,
  p_max_output_rows IN NUMBER,
  p_debug_mode      IN VARCHAR2,
  p_calling_from    IN VARCHAR2) IS

  l_doc_id         NUMBER;
  l_rel_id         NUMBER;
  l_trx_type       VARCHAR2(20);
  l_doc_subtype    VARCHAR2(25);
  l_preparer_id    NUMBER;
  l_app_path_id    NUMBER;
  l_ame_trx_type   PO_DOCUMENT_TYPES_ALL.AME_TRANSACTION_TYPE%TYPE;
  l_ame_app_id     NUMBER;
  l_ame_po_appr_id NUMBER;
  l_ame_trx_id     NUMBER;
  l_ame_po         BOOLEAN := false;
  l_created_by     NUMBER;
  l_from_date      VARCHAR2(25);
  l_item_type      WF_ITEMS.ITEM_TYPE%TYPE;
  l_item_key       WF_ITEMS.ITEM_KEY%TYPE;
  l_key            VARCHAR2(255);

  l_revision       VARCHAR2(25);
  l_date_char      VARCHAR2(30);
  l_run_date       VARCHAR2(30);
  l_date           DATE;
  l_instance       V$INSTANCE.INSTANCE_NAME%TYPE;
  l_apps_version   FND_PRODUCT_GROUPS.RELEASE_NAME%TYPE;
  l_host           V$INSTANCE.HOST_NAME%TYPE;
  l_step           VARCHAR2(5);
  l_counter        NUMBER;
  l_sql            VARCHAR2(4000);

  invalid_parameters EXCEPTION;

BEGIN
 
  -- Determine instance info
  l_step := '10';
  BEGIN

    SELECT max(release_name) INTO l_apps_version
    FROM fnd_product_groups;

    l_step := '20';
    SELECT instance_name, host_name
    INTO l_instance, l_host
    FROM v$instance;

  EXCEPTION WHEN OTHERS THEN
    print_log('Error in validate_parameters gathering instance information: '
      ||sqlerrm);
    raise;
  END;

  -- Check if customer has AME functionality for PO's
  IF l_apps_version like '12.1.3%' OR l_apps_version like '12.2%' THEN
    BEGIN
      SELECT count(*) INTO l_counter
      FROM dba_tab_columns
      WHERE table_name = 'PO_HEADERS_ALL'
      AND   column_name = 'AME_APPROVAL_ID';
    EXCEPTION WHEN OTHERS THEN
      l_counter := 0;
    END;
    IF l_counter > 0 THEN
      l_ame_po := true;
    END IF;
  END IF;


  g_max_output_rows := nvl(p_max_output_rows,20);
  g_debug_mode := nvl(p_debug_mode, 'Y');

  l_step := '25';  
  IF p_mode is null THEN
    print_error('Invalid Analyzer usage.'||
      'Refer to Doc ID 1525670.1 to download latest Approval Analyzer and for complete usage details.');
    raise invalid_parameters;
  END IF;


  l_step := '30';
  IF p_org_id is null THEN
    print_log('No operating unit organization ID specified. '||
      'The org_id parameter is mandatory.');
    raise invalid_parameters;
  END IF;
  IF p_from_date is null THEN
    print_error('No "From Date" specified. '||
      'The from_date parameter is mandatory.');
    raise invalid_parameters;
  END IF;

  l_from_date := to_char(nvl(p_from_date,sysdate-90),'DD-MON-YYYY');

  l_step := '40';
  IF (p_mode='SINGLE' AND nvl(p_trx_type,'XXX') NOT IN ('PA','PO','REQUISITION','RELEASE')) THEN 
    print_error('Invalid trx type specified.');
    print_error('Value should be one of PA, PO, REQUISITION, or RELEASE');
    raise invalid_parameters;      
  END IF;


  l_step := '45';
  IF (p_mode='SINGLE' AND (p_trx_num IS NULL OR p_trx_num='')) THEN
    print_error('Invalid trx number specified.');
    print_error('Transaction number must be entered');
    raise invalid_parameters;      
  END IF;
  

  l_step := '50';
  IF (p_release_num is not null AND
      (p_trx_type <> 'RELEASE' OR p_trx_num is null)) OR
     ((p_release_num is null OR p_trx_num is null) AND
      p_trx_type = 'RELEASE') THEN
    print_error('Invalid combination. For a release the transaction type '||
      'should be RELEASE and the release number and PO number '||
      'must both be provided');
    raise invalid_parameters;
  END IF;

  IF p_release_num is not null THEN
    l_step := '60';
    BEGIN
      SELECT h.po_header_id, r.po_release_id, r.release_type,
             r.wf_item_type, r.wf_item_key, r.created_by
      INTO   l_doc_id, l_rel_id, l_doc_subtype,
             l_item_type, l_item_key, l_created_by
      FROM   po_headers_all h, po_releases_all r
      WHERE  h.segment1 = p_trx_num
      AND    h.org_id = p_org_id
      AND    r.org_id = h.org_id
      AND    r.po_header_id = h.po_header_id
      AND    r.release_num = p_release_num;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      print_error('Invalid release, PO and org_id combination');
      print_error('No release document exists for values '||
        to_char(p_release_num)||'/'||p_trx_num||'/'||to_char(p_org_id));
      raise invalid_parameters;
    END;
  ELSIF p_trx_num is not null THEN
    IF p_trx_type is null OR p_trx_type = 'ANY' THEN
      print_error('You must specify the org_id and transaction type when '||
        'trx_number is specified.');
      raise invalid_parameters;
    ELSIF p_trx_type IN ('PA','PO') THEN
      l_step := '70';
      BEGIN
        IF l_ame_po THEN
          l_sql :=
            'SELECT po_header_id, type_lookup_code, created_by,
                    wf_item_type, wf_item_key,
                    ame_approval_id, ame_transaction_type
             FROM   po_headers_all
             WHERE  segment1 = :1
             AND    ((:2= ''PA'' AND
                      type_lookup_code IN (''BLANKET'',''CONTRACT'')) OR
                     (:3= ''PO'' AND
                      type_lookup_code IN (''STANDARD'',''PLANNED'')))
             AND    org_id = :4
             AND    rownum = 1';
          EXECUTE IMMEDIATE l_sql
            INTO l_doc_id, l_doc_subtype, l_created_by,
                 l_item_type, l_item_key,
                 l_ame_po_appr_id, l_ame_trx_type
            USING IN p_trx_num, IN p_trx_type, IN p_trx_type, IN p_org_id;
        ELSE
          l_sql :=
            'SELECT po_header_id, type_lookup_code, created_by,
                    wf_item_type, wf_item_key
             FROM   po_headers_all
             WHERE  segment1 = :1
             AND    ((:2= ''PA'' AND
                      type_lookup_code IN (''BLANKET'',''CONTRACT'')) OR
                     (:3= ''PO'' AND
                      type_lookup_code IN (''STANDARD'',''PLANNED'')))
             AND    org_id = :4
             AND    rownum = 1';
          EXECUTE IMMEDIATE l_sql
            INTO l_doc_id, l_doc_subtype, l_created_by,
                 l_item_type, l_item_key
            USING IN p_trx_num, IN p_trx_type, IN p_trx_type, IN p_org_id;
        END IF;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        print_error('Invalid transaction type, number, and org_id combination');
        print_error('No document exists for values '||p_trx_type||
          '/'||p_trx_num||'/'||to_char(p_org_id));
        raise invalid_parameters;
      END;
    ELSIF p_trx_type = 'REQUISITION' THEN
      l_step := '80';
      BEGIN
        SELECT requisition_header_id, type_lookup_code,
               created_by, wf_item_type, wf_item_key
        INTO   l_doc_id, l_doc_subtype, l_created_by,
               l_item_type, l_item_key
        FROM   po_requisition_headers_all
        WHERE  segment1 = p_trx_num
        AND    org_id = p_org_id;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        print_error('Invalid transaction type, number, and org_id combination');
        print_error('No document exists for values '||p_trx_type||
          '/'||p_trx_num||'/'||to_char(p_org_id));
        raise invalid_parameters;
      END;
    END IF;
  END IF;
  
  IF p_trx_type IN ('PA','PO') AND
     l_doc_subtype IN ('CONTRACT','BLANKET') THEN
    l_trx_type := 'PA';
  ELSE
    l_trx_type := p_trx_type;
  END IF;

  l_step := '90';
  IF l_doc_id is not null THEN
  -- Get the preparer employee ID and approval path from actions
    BEGIN
      SELECT employee_id, approval_path_id
      INTO   l_preparer_id, l_app_path_id
      FROM po_action_history
      WHERE object_id = l_doc_id
      AND   object_type_code = l_trx_type
      AND   action_code = 'SUBMIT'
      AND   sequence_num = (
              SELECT max(sequence_num)
              FROM po_action_history
              WHERE object_id = l_doc_id
              AND   object_type_code = l_trx_type

              AND   action_code = 'SUBMIT');
    EXCEPTION WHEN NO_DATA_FOUND THEN
      l_preparer_id := null;
    END;

    -- If not found use the created by on the document header
    l_step := '100';
    IF l_preparer_id is null THEN
      BEGIN
        SELECT employee_id INTO l_preparer_id
        FROM fnd_user
        WHERE user_id = l_created_by;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        l_preparer_id := null;
      END;
    END IF;

    -- Get the approval method
    l_step := '110';
    BEGIN
      SELECT decode(sp.use_positions_flag,
               'Y', 'POSITION',
               'N', 'SUPERVISOR',
               null)
      INTO g_app_method
      FROM financials_system_params_all sp
      WHERE sp.org_id = p_org_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      g_app_method := null;
    END;

    -- Get default approval path if not already populated
    l_step := '120';
    IF g_app_method = 'POSITION' AND l_app_path_id is null THEN
      BEGIN
        SELECT default_approval_path_id
        INTO   l_app_path_id
        FROM po_document_types_all
        WHERE org_id = p_org_id
        AND   document_type_code = l_trx_type
        AND   document_subtype = l_doc_subtype;
      EXCEPTION WHEN NO_DATA_FOUND THEN
        l_app_path_id := null;
      END;
    END IF;

    -- Check if AME is in use for PO and REQUISITION documents
    -- Get the AME application ID for signature queries
    l_step := '130';
    g_use_ame := false;
    
    IF l_trx_type = 'REQUISITION' THEN
      BEGIN
        SELECT dt.ame_transaction_type, ca.application_id
        INTO l_ame_trx_type, l_ame_app_id
        FROM po_document_types_all dt,
             ame_calling_apps ca
        WHERE dt.org_id = p_org_id
        AND   dt.document_type_code = l_trx_type
        AND   dt.document_subtype = l_doc_subtype
        AND   ca.transaction_type_id = dt.ame_transaction_type
        AND   ca.fnd_application_id = 201
        AND   sysdate BETWEEN ca.start_date AND
                nvl(ca.end_date,sysdate);
      EXCEPTION WHEN NO_DATA_FOUND THEN
        l_ame_trx_type := null;
      END;
                
      IF (l_ame_trx_type is not null) THEN
        g_use_ame := true;
        l_ame_trx_id := l_doc_id;
      END IF;
    ELSIF (l_trx_type IN ('PA','PO') AND l_ame_po_appr_id is not null) THEN 
      g_use_ame := true;
      l_ame_trx_id := l_ame_po_appr_id;
      BEGIN
        SELECT ca.application_id INTO l_ame_app_id
        FROM ame_calling_apps ca
        WHERE ca.transaction_type_id = l_ame_trx_type
        AND   ca.fnd_application_id = 201
        AND   sysdate BETWEEN ca.start_date AND
                nvl(ca.end_date,sysdate);
      EXCEPTION WHEN NO_DATA_FOUND THEN
        l_ame_app_id := null; 
      END;
    END IF;
  END IF;


  -- Revision and date values populated by RCS
  l_revision := rtrim(replace('$Revision: 200.7 $','$',''));
  l_revision := ltrim(replace(l_revision,'Revision:',''));
  l_date_char := rtrim(replace('$Date: 2015/10/05 10:30:00 $','$',''));
  l_date_char := ltrim(replace(l_date_char,'Date:',''));
  l_date_char := to_char(to_date(l_date_char,'YYYY/MM/DD HH24:MI:SS'),'DD-MON-YYYY');

  -- Create global hash for report information
  g_rep_info('Host') := l_host;
  g_rep_info('Instance') := l_instance;
  g_rep_info('Apps Version') := l_apps_version;
  g_rep_info('File Name') := 'po_approval_analyzer.sql';
  g_rep_info('File Version') := l_revision;
  g_rep_info('File Date') := l_date_char;
  g_rep_info('Execution Date') := to_char(sysdate,'DD-MON-YYYY HH24:MI:SS');
  g_rep_info('Calling From') := p_calling_from;  
  g_rep_info('Description') := ('The ' || analyzer_title ||' Analyzer ' || '<a href="https://support.oracle.com/epmos/faces/DocumentDisplay?id=1525670.1" target="_blank">(Note 1525670.1)</a> ' || ' is a self-service health-check script that reviews the overall footprint, analyzes current configurations and settings for the environment and provides feedback and recommendations on best practices. Your application data is not altered in any way when you run this analyzer.');

-- Validation to verify analyzer is run on proper e-Business application version
-- In case validation at the beginning is updated/removed, adding validation here also so execution fails
  IF substr(l_apps_version,1,2) < '12' THEN
	print_log('eBusiness Suite version = '||l_apps_version);
	print_log('ERROR: This Analyzer script must run in version 12 or above.');
	raise invalid_parameters;
  END IF;
  
  -- Create global hash for parameters. Numbers required for the output order
  g_parameters('1. Mode') := p_mode;  
  g_parameters('2. Operating Unit') := p_org_id;
  g_parameters('3. Trx Type') := p_trx_type;
  g_parameters('4. Trx Number') := p_trx_num;
  g_parameters('5. Release Number') := p_release_num;
  --g_parameters('5. Include WF Status') := p_include_wf;  
  g_parameters('6. From Date') := l_from_date;
  g_parameters('7. Max Rows') := g_max_output_rows;
  g_parameters('8. Debug Mode') := p_debug_mode;

  -- Create global hash of SQL token values
  g_sql_tokens('##$$REL$$##') := g_rep_info('Apps Version');
  g_sql_tokens('##$$DOCNUM$$##') := p_trx_num;  
  g_sql_tokens('##$$TRXTP$$##') := l_trx_type;
  g_sql_tokens('##$$SUBTP$$##') := l_doc_subtype;
  g_sql_tokens('##$$ORGID$$##') := to_char(p_org_id);
  g_sql_tokens('##$$DOCID$$##') := nvl(to_char(l_doc_id),'NULL');
  g_sql_tokens('##$$RELID$$##') := nvl(to_char(l_rel_id),'NULL');
  g_sql_tokens('##$$PREPID$$##') := nvl(to_char(l_preparer_id),'NULL');
  g_sql_tokens('##$$FDATE$$##') := l_from_date;
  g_sql_tokens('##$$ITMTYPE$$##') := l_item_type;
  g_sql_tokens('##$$ITMKEY$$##') := l_item_key;
  g_sql_tokens('##$$APPATH$$##') := nvl(to_char(l_app_path_id),'NULL');
  g_sql_tokens('##$$AMETRXTP$$##') := l_ame_trx_type;
  g_sql_tokens('##$$AMEAPPID$$##') := nvl(to_char(l_ame_app_id),'NULL');
  g_sql_tokens('##$$AMETRXID$$##') := nvl(to_char(l_ame_trx_id),'NULL');
  
  IF (l_trx_type = 'REQUISITION') THEN
      g_sql_tokens('##$$DOCTYPESHORT$$##') := 'REQ';
  ELSIF (l_trx_type = 'PA') THEN
      g_sql_tokens('##$$DOCTYPESHORT$$##') := 'PO';
  ELSE
      g_sql_tokens('##$$DOCTYPESHORT$$##') := l_trx_type;
  END IF;  
  

  l_step := '140';
  l_key := g_sql_tokens.first;
  -- Print token values to the log
 
  print_log('SQL Token Values');

  WHILE l_key IS NOT NULL LOOP
    print_log(l_key||': '|| g_sql_tokens(l_key));
    l_key := g_sql_tokens.next(l_key);
  END LOOP;



EXCEPTION
  WHEN INVALID_PARAMETERS THEN
    print_log('Invalid parameters provided. Process cannot continue.');
    raise;
  WHEN OTHERS THEN
    print_log('Error validating parameters: '||sqlerrm);
    raise;
END validate_parameters;


---------------------------------------------
-- Load signatures for this ANALYZER       --
---------------------------------------------
PROCEDURE load_signatures IS
  l_info  HASH_TBL_4K;
  l_dynamic_SQL VARCHAR2(8000);  
BEGIN
  -------------------------------------------
  -- Workflow health
  -------------------------------------------
  add_signature(
   'WF_OVERALL_HEALTH',                 -- Signature ID
   'SELECT (
            SELECT to_char(round(sysdate-(min(begin_date)),0))||
                   '' Days''
            FROM wf_items
            WHERE end_date is not null
           ) "Oldest Closed WF Item",
           (
            SELECT count(item_key)
            FROM wf_items
            WHERE end_date is not null
           ) "Closed WF Items",
           (
            SELECT count(notification_id)
            FROM wf_notifications
            WHERE end_date is not null
           ) "Closed WF Notifications"
    FROM DUAL',                                   -- SQL
   'Overall Workflow Health',                     -- User signature name (title in report)
   '[Oldest Closed WF Item] > [365]',             -- Fail condition
   'Overall health status of Workflow requires action,
    there are closed workflow items over 1 year old',      -- Problem description
   '<ul>
   <li>Run the "Purge Obsolete Workflow Runtime Data" process
       as indicated in step 1 of [458886.1].</li>
   <li>If after running the purge process these counts are not reduced,
       continue with the subsequent steps in [458886.1] </li>
  <li>Run the Workflow Analyzer Tool found in [1369938.1] to determine 
      if there are items for additional workflows that should be purged
      and what other steps you can take to review your overall 
      workflow footprint.</li>
  </ul>',                -- Solution HTML
   NULL,                 -- Success message if printing success (non default)
   'ALWAYS',             -- Print condition ALWAYS, SUCCESS, FAILURE, NEVER
   'W',                  -- If fails what type is it ? E: error, W: warning, I: info
   'RS',                 -- Print SQL Output (Y, N, RS = only if rows selected)
   'Y');                 -- Limit output rows to the max rows value

  -------------------------------------------
  -- Invalids
  -------------------------------------------
  add_signature(
   'PO_INVALIDS',
   'SELECT a.object_name,
           decode(a.object_type,
             ''PACKAGE'', ''Package Spec'',
             ''PACKAGE BODY'', ''Package Body'',
             a.object_type) type,
           (
             SELECT ltrim(rtrim(substr(substr(c.text, instr(c.text,''Header: '')),
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 1),
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 2) -
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 1)
               ))) || '' - '' ||
               ltrim(rtrim(substr(substr(c.text, instr(c.text,''Header: '')),
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 2),
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 3) -
               instr(substr(c.text, instr(c.text,''Header: '')), '' '', 1, 2)
               )))
             FROM dba_source c
             WHERE c.owner = a.owner
             AND   c.name = a.object_name
             AND   c.type = a.object_type
             AND   c.line = 2
             AND   c.text like ''%$Header%''
           ) "File Version",
           b.text "Error Text"
    FROM dba_objects a,
         dba_errors b
    WHERE a.object_name = b.name(+)
    AND a.object_type = b.type(+)
    AND a.owner = ''APPS''
    AND (a.object_name like ''PO%'' OR
         a.object_name like ''ECX%'' OR
         a.object_name like ''XLA%'')
    AND a.status = ''INVALID''',
   'Purchasing Related Invalid Objects',
   'RS',
   'There exist invalid Purchasing related objects',
   '<ul>
      <li>Recompile the individual objects or recompile the
          entire APPS schema with adadmin</li>
      <li>Review any error messages provided and see [1527251.1]
          for details on compiling these invalid objects.</li>
   </ul>',
   NULL,
   'ALWAYS',
   'E',
   p_include_in_dx_summary => 'Y');

  ------------------------------------------
  -- Max Extents and Space Issues
  ------------------------------------------
  add_signature(
   'TABLESPACE_CHECK',
   'SELECT s.segment_name object_name,
           s.owner,
           s.tablespace_name tablespace,
           s.segment_type object_type,
           s.extents extents,
           s.max_extents max_extents,
           s.next_extent/1024/1024 next_extent,
           max(fs.bytes)/1024/1024 max,
           sum(fs.bytes)/1024/1024 free
    FROM dba_segments     s,
         dba_free_space   fs
    WHERE s.segment_type IN (''TABLE'',''INDEX'')
    AND   s.segment_name like ''PO\_%'' escape ''\''
    AND   fs.tablespace_name = s.tablespace_name
    GROUP BY s.tablespace_name, s.owner, s.segment_type,
           s.segment_name, s.extents, s.max_extents, s.next_extent
    HAVING (s.extents >= (s.max_extents - 2) OR
            s.next_extent > max(fs.bytes))
    ORDER BY extents desc',
   'Potential Space and Extents Issues',
   'RS',
    'The objects listed above are either approaching their
     maximum number or extents, or have a next extent size
     that is larger than the largest available block of
     free space in the tablespace.',
   '<ul> <li>Review items indicated and increase the max extents or add
    additional data files to the tablespace as required</li></ul>',
   null,
   'FAILURE',
   'W',
   'RS');

  -------------------------------------------
  -- Approval workflw set to Background and
  -- background process not scheduled.
  -------------------------------------------
  add_signature(
   'PO_WORKFLOW_APPROVAL_MODE',
   'SELECT pov.setting_level,
           pov.option_value
    FROM (
           SELECT ''10001-Site'' Setting_Level,
                  nvl(profile_option_value,''BACKGROUND'') Option_Value
           FROM fnd_profile_option_values v,
                fnd_profile_options o
           WHERE o. profile_option_name = ''PO_WORKFLOW_APPROVAL_MODE''
           AND   v.profile_option_id (+) = o.profile_option_id
           AND   v.application_id (+) = o.application_id
           AND   v.level_id (+) = 10001
           AND   nvl(v.profile_option_value,''BACKGROUND'') = ''BACKGROUND''
           UNION
           SELECT decode(v.level_id,
                    10002, ''10002-Appl: ''||a.application_name,
                    10003, ''10003-Resp: ''||r.responsibility_name,
                    10004, ''10004-User: ''||u.user_name),
                  v.profile_option_value
           FROM fnd_profile_option_values v,
                fnd_profile_options o,
                fnd_application_vl a,
                fnd_responsibility_vl r,
                fnd_user u
           WHERE o. profile_option_name = ''PO_WORKFLOW_APPROVAL_MODE''
           AND   v.profile_option_value = ''BACKGROUND''
           AND   v.level_id IN (10002,10003,10004)
           AND   v.level_value = decode(v.level_id,
                   10004, u.user_id, 10003, r.responsibility_id,
                   10002, a.application_id, -1)
           AND   v.profile_option_id = o.profile_option_id
           AND   v.application_id = o.application_id
           AND   a.application_id (+) = v.level_value
           AND   r.responsibility_id (+) = v.level_value
           AND   u.user_id (+) = v.level_value
         ) pov
    WHERE (NOT EXISTS (
            SELECT 1
            FROM fnd_concurrent_requests r,
                 fnd_concurrent_programs p
            WHERE p.concurrent_program_name = ''FNDWFBG''
            AND   p.application_id = 0
            AND   r.program_application_id = p.application_id
            AND   r.concurrent_program_id = p.concurrent_program_id
            AND   nvl(r.phase_code,''P'') <> ''C''
            AND   nvl(r.resubmit_interval,-1) > 0
            AND   nvl(r.resubmit_end_date, sysdate+1) >= sysdate
            AND   nvl(r.argument1,''POAPPRV'') = ''POAPPRV'') OR
           NOT EXISTS (
            SELECT 1
            FROM fnd_concurrent_requests r,
                 fnd_concurrent_programs p
            WHERE p.concurrent_program_name = ''FNDWFBG''
            AND   p.application_id = 0
            AND   r.program_application_id = p.application_id
            AND   r.concurrent_program_id = p.concurrent_program_id
            AND   nvl(r.phase_code,''P'') <> ''C''
            AND   nvl(r.resubmit_interval,-1) > 0
            AND   nvl(r.resubmit_end_date, sysdate+1) >= sysdate
            AND   nvl(r.argument1,''REQAPPRV'') = ''REQAPPRV''))
    ORDER BY 1,2',
   'PO:Workflow Processing Mode Set to Background',
   'RS',
   'The profile option PO:Workflow Processing Mode is Set to "Background"
    at some level, and there is no "Workflow Background Process"
    concurrent program scheduled, either for Purchase Orders or
    Requisitions',
   '<ul>
<li>Review the settings indicated above</li>
<li>Either change these settings to "Online" OR </li>
<li>Insure that the concurrent program "Workflow Background Process"
    is scheduled to run regularly for the "PO Approval" and
    "PO Requisition Approval" item types.</li>
</ul>',
   null,
   'FAILURE',
   'E',
   'RS',
   p_include_in_dx_summary => 'Y');

  -------------------------------------------
  -- Approval  Management Engine is Enabled
  -------------------------------------------
  add_signature(
   'AME_ENABLED',
   'SELECT dt.type_name,
           dt.document_type_code,
           dt.document_subtype,
           dt.ame_transaction_type,
           dt.wf_approval_itemtype,
           dt.wf_approval_process
    FROM po_document_types_all dt
    WHERE dt.org_id = ##$$ORGID$$##
    AND   dt.document_type_code = ''REQUISITION''
    AND   dt.ame_transaction_type IN (
            ''INTERNAL_REQ'',''PURCHASE_REQ'')',
   'Approvals Management Engine (AME) Enabled',
   'RS',
   'The Approvals Management Engine (AME) is enabled for the
    listed document types in this operating unit',
   '<ul>
<li>If you have intentionally enabled AME, you may ignore this warning</li>
<li>If not, you should disable AME for these document types:
   <ol>
     <li>Query up the document type in the Purchasing &gt;
         Document Types form.</li>
     <li>Delete the value in the "Approval Transaction Type" field.
         This will be PURCHASE_REQ for Purchase Requisitions and
         INTERNAL_REQ for Internal Requisitions.</li>
      <li>See [470204.1] for details and screen shots.</li></ol>
   </li></ul>',
   null,
   'FAILURE',
   'W',
   'RS');



/*#################################
  # Document Manager Errors       #
  #################################*/
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN
             (''IN PROCESS'', ''PRE-APPROVED'')
    AND   wiav.text_value is NULL
    AND   EXISTS (
            SELECT 1
            FROM wf_item_attribute_values wiav2,
                 wf_item_attributes wia2
            WHERE wiav2.item_type = wiav.item_type
            AND   wiav2.item_key = wiav.item_key
            AND   wia2.item_type = wiav2.item_type
            AND   wia2.name = wiav2.name
            AND   wiav2.name in (''RESPONDER_APPL_ID'', ''RESPONDER_RESP_ID'')
            AND   wia2.type <> ''EVENT''
            AND   substr(nvl(wiav2.text_value, nvl(to_char(wiav2.number_value),
                    to_char(wiav2.date_value,''DD-MON-YYYY hh24:mi:ss''))),1,15)
                    = ''-1'')';
                    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;       
   
  -------------------------------------------
  -- Note 1310935.1, case #1
  -------------------------------------------
  add_signature(
   'Note1310935.1_case_1',
   l_dynamic_SQL,
   'Workflow Responder Application Id or Responsibility Id Incorrectly Set',
   'RS',
   'Found transactions with responder application id or responder resposibility
    id incorrectly set to -1',
   '<ul>
<li>Apply {9362974}</li>
<li>If patch is applied and workflow is customized please follow
    instructions in [763086.1]</li>
<li>If issue is still not solved after actions above:</li>
<ol>
<li>Generate and collect debug and trace as documented in [409155.1]</li>
<li>Rerun this same report with the affected transaction id</li>
<li>Log a Service Request and provide the files above
</ol>
<li>Source KB Article: [1310935.1]</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');
   
 l_dynamic_SQL := '';  
   
  -------------------------------------------
  -- Note 1304639.1, case #1
  -------------------------------------------

  l_dynamic_SQL :=    'SELECT ''Purchase Order'' Transaction_Type,
       poh.segment1 Transaction_Number,
       poh.org_id Organization_Id,
       poh.authorization_status Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type = wiav.item_type
    AND   poh.wf_item_key = wiav.item_key
    AND   poh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   EXISTS 
             (SELECT 1
              FROM  po_distributions_all pda,
                    mtl_reservations mr
              WHERE pda.po_header_id = poh.po_header_id
              AND   pda.amount_delivered >= pda.amount_ordered
              AND   pda.po_header_id = mr.supply_source_header_id
              AND   pda.po_line_id = mr.supply_source_line_id)';
              
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
       l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
   END IF;       
    
  
  add_signature(
   'Note1304639.1_case_1',
   l_dynamic_SQL,
   'Orphan reservation existing for the Purchase Order (PO) shipment which has already been received and delivered',
   'RS',
   'Found orphan reservations for the current Purchase Order (PO) shipment which has already been received and delivered 
    and approve:60 and do_action:110 APIs error',
   '<ul>
<ol>
<li>Open the reservations form.<br>Navigation: from the Inventory Responsibility -> On hand availability -> Reservations</li>
<li>Query the PO supply reservation associated with the affected line.</li>
<li>Delete this reservation.</li>
</ol>
<li>Source KB Article: [1304639.1] section 1</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');
   
   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1304639.1, case #2
  -------------------------------------------
    
   l_dynamic_SQL := 'SELECT ''Purchase Order'' Transaction_Type,
       poh.segment1 Transaction_Number,
       pol.item_id Item_Id,
       poh.org_id Organization_Id,
       poh.authorization_status Authorization_Status
  FROM wf_item_attribute_values wiav,
       wf_item_attributes wia,
       wf_items wfi,
       wf_notifications wfn,
       po_headers_all poh,
       po_lines_all pol,
       mtl_system_items msi
 WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type = wiav.item_type
    AND   poh.wf_item_key = wiav.item_key
    AND   poh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   pol.po_header_id = poh.po_header_id
    AND   pol.item_id = msi.inventory_item_id
       /*No more than 10 years lead processing time*/
    AND   (msi.postprocessing_lead_time > 3650 or
            msi.postprocessing_lead_time < -3650)';
            
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
       l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
   END IF;   
  
  add_signature(
   'Note1304639.1_case_2',
   l_dynamic_SQL,
   'Excessive Item lead post-processing time and NULL sysadmin error message',
   'RS',
   'Found transactions which have items with excessive lead post-processing
    time and approve:60 and do_action:110 APIs encounter error',
   '<ul>
<li>Perform the following steps for each item found in the table above:</li>
<ol>
<li>From the Master Items form for the Inventory Organization query the item used in the PO</li>
<li>Enter a lead time of less than 3650 or more than -3650</li>
<li>Save and retry</li>
</ol>
<li>Source KB Article: [1304639.1] section 2</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');

  l_dynamic_SQL := '';
  
  -------------------------------------------
  -- Note 1304639.1, case #3
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT ''Requisition'' Transaction_Type,
       prh.segment1 Transaction_Number,
       trg.trigger_name Trigger_Name,
       prh.org_id Organization_Id,
       prh.authorization_status Authorization_Status
  FROM wf_item_attribute_values wiav,
       wf_item_attributes wia,
       wf_items wfi,
       wf_notifications wfn,
       po_requisition_headers_all prh,
       all_triggers trg
 WHERE wiav.item_type = ''REQAPPRV''
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   prh.wf_item_type = wiav.item_type
    AND   prh.wf_item_key = wiav.item_key
    AND   prh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   trg.table_name = ''PO_REQUISITIONS_INTERFACE_ALL''
    AND   trg.status = ''ENABLED''
    AND   trg.trigger_name <> ''PO_REQUISITIONS_INTERFACE_BRI''';
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION')  THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
   END IF;       
  
  add_signature(
   'Note1304639.1_case_3',
   l_dynamic_SQL,
   'Non Purchasing Triggers active in Requisition Interface',
   'RS',
   'Found non standard and enabled PO triggers in Requisition Interface
    and approve:60 and do_action:110 APIs error',
   '<ul>
<li>Review non-standard PO triggers listed above for the following problems:</li>
<ol>
<li>Trigger is updating Requisition in interface table to "Incomplete" status</li>
<li>requisition import is run with parameter Initiate Approvals set to YES</li>
</ol>
<li>Source KB Article: [1304639.1] section 3</li>
</ul>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');
   
   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1304639.1, case #4
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:po_req_supply ''||
            ''returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:110:''||
            ''unexpected error in action call%''
    AND   NOT EXISTS (
               SELECT 1
               FROM fnd_profile_option_values povl
               WHERE povl.profile_option_id = 1266
               AND   ((povl.level_id = 10001) OR
                      (povl.level_id = 10002 AND
                       povl.level_Value = 201))
               AND   povl.profile_option_value is not null)';
               
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;
   
  add_signature(
   'Note1304639.1_case_4',
   l_dynamic_SQL,
   'Unset Profile option "INV: Replenishment Count Requisition Approval"
    affecting requisitions when doing replenishment',
   'RS',
   'Found that profile "INV: Replenishment Count Requisition Approval"
    is not set at SITE or PURCHASING level which may affect requisitions',
   '<ul>
<li>Profile option "INV: Replenishment Count Requisition Approval" must
    be set for processing Requisitions, otherwise it may trigger
    approval errors</li>
<li>Approval errors of this type have been found in this instance</li>
<li>AND profile option has not been found set at SITE or Purchasing Application level</li>
<li>While it is not mandatory to have it at SITE or Purchasing Application
    level, it is an indication that if not set at USER or RESP level there
    will be no value and the problem will occur</li>
<li>Please perform</li>
<ol>
<li>Set the profile option at the SITE or Purchasing Application level to some value</li>
<li>If a default value at those levels cant be set for some business reason,
    insure that every user entering Requisitions has the profile set at their
    level or their responsibility level</li>
<li>You will find a SQL to check the profile at all levels in the
    source KB Article [1304639.1] section 4</li>
</ol>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');

   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1304639.1, case #5
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(pol.po_line_id,prl.requisition_line_id) Line_Id,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh,
         po_lines_all pol,
         po_requisition_lines_all prl
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT''||
            ''.do_action:110:unexpected error in action call%''
    AND   poh.po_header_id = pol.po_header_id(+)
    AND   prh.requisition_header_id = prl.requisition_header_id(+)
    AND   nvl(pol.unit_meas_lookup_code,prl.unit_meas_lookup_code) is NULL';
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;      
  
  add_signature(
   'Note1304639.1_case_5',
   l_dynamic_SQL,
   'Missing Unit of Measure in Requisition or Purchase Order Line',
   'RS',
   'Found that requisition or purchase order line(s) have missing UOM',
   '<ul>
<li>First prevent this problem from happening again:</li>
<ol>
<li>Query the PO/REQ listed above and check the line type for Line_Id listed</li>
<li>In a Purchasing Responsibility navigate to: Setup, Purchasing, Line Types</li>
<li>Query the line type and select a suitable value from the LOV for the Amount field</li>
<li>Make the same check for all line types</li>
</ol>
<li>You need to log a Service Request with Oracle Customer Support to get a
    datafix for these transactions</li>
<li>Please upload this report to the Service Request</li>
<li>Source KB Article: [472763.1] section 5</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');

   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1304639.1, case #6
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT ''Requisition'' Transaction_Type,
       prh.segment1 Transaction_Number,
       prh.org_id Organization_Id,
       prh.authorization_status Authorization_Status
  FROM wf_item_attribute_values wiav,
       wf_item_attributes wia,
       wf_items wfi,
       wf_notifications wfn,
       po_requisition_headers_all prh
 WHERE wiav.item_type = ''REQAPPRV''
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   prh.wf_item_type = wiav.item_type
    AND   prh.wf_item_key = wiav.item_key
    AND   prh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
       /* and wfn.subject like ''Document Manager Failed%'' */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   prh.interface_source_code = ''CTO'' /*back to back order*/';
    
    
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
   END IF;   
  
  add_signature(
   'Note1304639.1_case_6',
   l_dynamic_SQL,
   'Back to Back Order with approve:60 and do_action:110 APIs error',
   'RS',
   'Found back to back order(s) with approve:60 and do_action:110 APIs error',
   '<ul>
<li>Back to back orders were found to have errors in approval
    manager specifically at APIs po_req_supply and do_action.
    While this test is not 100% accurate, it is likely these
    back to back orders are hitting Bug:10229709</li>
<li>Please perform the following if these back to back orders cant be approved:</li>
<ol>
<li>Re-run this report with the transaction number of the affected transaction</li>
<li>Log a Service Request with Oracle GCS and upload the output of this report</li>
</ol>
<li>Source KB Article: [1304639.1] section 6</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');

   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1304639.1, case #7
  -------------------------------------------
  
  l_dynamic_SQL :=  'SELECT distinct ''Requisition'' Transaction_Type,
       prh.segment1 Transaction_Number,
       prh.org_id Organization_Id,
       prh.authorization_status Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_requisition_headers_all prh,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   prh.wf_item_type = wiav.item_type
    AND   prh.wf_item_key = wiav.item_key
    AND   prh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:60:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   prh.interface_source_code <> ''CTO''
    AND   ''12.1'' = substr(''##$$REL$$##'',1,4)
    AND   FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.26.12010000.19'') = ''<''
    AND   als.type = ''PACKAGE BODY''
    AND   als.name = ''INV_MAINTAIN_RESERVATION_PUB''
    AND   als.text like ''%$Header%''';
  
  add_signature(
   'Note1304639.1_case_7',
   l_dynamic_SQL,
   'Code error for imported requisitions (Release 12.1.x only)',
   'RS',
   'Found transaction(s) with approve:60 and do_action:110 APIs error
    where the version of INVPMRVB.pls is less than 120.26.12010000.19',
   '<ul>
<li>File INVPMRVB.pls is less than version 120.26.12010000.19 and
    at least one transaction presents the error that may be caused
    by this older code</li>
<li>In versions older than 120.26.12010000.19, Inventory tries to create
    a reservation regardless of the origin of the requisition.
    If the requisition is no sales order based, it should not try
    to create reservation</li>
<li>Please apply {13580940} and retry the transaction from the
    notification window "retry" button (more information in [312582.1])</li>
<li>Source KB Article [1304639.1] section 7</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   'RS',
   p_include_in_dx_summary => 'Y');

   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1116134.1
  -------------------------------------------
  
  l_dynamic_SQL :=  'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.reject:210:''||
            ''po_req_supply returned false%po.plsql.PO_DOCUMENT_ACTION_PVT.''||
            ''do_action:110:unexpected error in action call%''
    AND   ((''12.1'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.2.12010000.4'') = ''<'' ) OR
           (''12.0'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.2.12000000.4'') = ''<'' ))
    AND als.type = ''PACKAGE BODY''
    AND als.name = ''PO_DOCUMENT_ACTION_AUTH''
    AND als.text like ''%$Header%''';
    
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;     
  
  add_signature(
   'Note1116134.1',
   l_dynamic_SQL,
   'Reject of back to back orders error in reject:210 and do_action:110 APIs',
   'RS',
   'Found transaction(s) with error in reject:210 and do_action:110
    APIs where version of POXDAAPB.pls is less than
    120.2.12000000.4/120.2.12010000.4',
   '<ul>
<li>Please apply {9488727}</li>
<li>Retest:</li>
<ol>
<li>Back to Order Process</li>
<li>Create an Item with ATO option</li>
<li>Create a Sales Order for that item</li>
<li>Create a Purchase order from the generated requisition</li>
<li>Submit for Approve</li>
<li>Log in as approver and reject</li>
</ol>
<li>To resubmit the document that is in error follow instruction in [312582.1]</li>
<li>Source KB Article: [1116134.1]</li>
</ul>',
   NULL,
   'FAILURE',
   'E',
   'RS',
   p_include_in_dx_summary => 'Y');

   l_dynamic_SQL := '';

  -------------------------------------------
  -- Note 867855.1
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT ''Blanket Release'' Transaction_Type,
           poh.segment1 PO_Number,
           pr.release_num Release_Num,
           pr.org_id Organization_Id,
           pr.authorization_status Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_releases_all pr,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.po_header_id = pr.po_header_id
    AND   pr.wf_item_type = wiav.item_type
    AND   pr.wf_item_key = wiav.item_key
    AND   pr.authorization_status IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_CLOSE.auto_update_close_status:30:''||
            ''100ORA-01403: no data found%''||
            ''po.plsql.PO_DOCUMENT_ACTION_CLOSE.auto_close_po:120:''||
            ''unexpected error in updating closed status%''||
            ''po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:110:''||
            ''unexpected error in action call''
    AND   ((''12.1'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.9.12010000.3'') = ''<'' ) OR
           (''12.0'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                '' '',1,1)-1),
              ''120.9.12000000.3'') = ''<'' ))
    AND   als.type = ''PACKAGE BODY''
    AND   als.name = ''PO_DOCUMENT_ACTION_CLOSE''
    AND   als.text like ''%$Header%'' ';
    
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'RELEASE') THEN
       l_dynamic_SQL := l_dynamic_SQL || ' AND pr.po_release_id = ##$$DOCID$$##';
   END IF;
  
   IF (g_sql_tokens('##$$REL$$##') IS NOT NULL) THEN
      IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') THEN
           add_signature(
            'Note867855.1',
            l_dynamic_SQL,
            'Releases Stuck with Error in auto_update_close_status:30:100 ORA-1403',
            'RS',
            'Found transactions which have errors in auto_update_close_status:30:100ORA-01403
             and auto_close_po:120 and the POXDACLB.pls version is
             less than 120.9.12000000.3',
            '<ul>
         <li>Please apply {8566664}</li>
         <li>To resubmit the document that is in error follow instructions in [312582.1]</li>
         <li>Source KB Article: [867855.1]</li>
         </ul>',
            null,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');
      ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
           add_signature(
            'Note867855.1',
            l_dynamic_SQL,
            'Releases Stuck with Error in auto_update_close_status:30:100 ORA-1403',
            'RS',
            'Found transactions which have errors in auto_update_close_status:30:100ORA-01403
             and auto_close_po:120 and the POXDACLB.pls version is
             less than 120.9.12010000.3',
            '<ul>
         <li>Please apply {8566664}</li>
         <li>To resubmit the document that is in error follow instructions in [312582.1]</li>
         <li>Source KB Article: [867855.1]</li>
         </ul>',
            null,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');      
      END IF;
   END IF;  
  
   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 1073703.1
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
             1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
             '' '',1,1)-1) po_employees_sv_version,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.DOCUMENT_ACTION_CHECK.authority_checks_setup:40:100 ''||
            ''ORA-01403: no data found%po.plsql.PO_DOCUMENT_ACTION_CHECK.''||
            ''authority_check:20:unexpected error in authority_checks_setup''||
            ''%po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:110:unexpected error ''||
            ''in action call''
    AND   als.type = ''PACKAGE BODY''
    AND   als.name = ''PO_EMPLOYEES_SV''
    AND   als.text like ''%$Header%''';
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;      
   
   
   IF (g_sql_tokens('##$$REL$$##') IS NOT NULL) THEN
      IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') THEN
           add_signature(
            'Note1073703.1',
            l_dynamic_SQL,
            'Document Manager error in authority_checks_setup:40:100
             ORA-01403 and authority_check:20 APIs',
            'RS',
            'Found transaction(s) with error in authority_checks_setup:40:100

             ORA-01403 and authority_check:20 APIs',
            '<ul>
         <li>Review version of package PO_EMPLOYEES_SV in column PO_EMPLOYEES_SV_VERSION above</li>
         <li>If less than 120.2.12000000.2 then apply {9150201}</li>
         <li>Otherwise (version is correct) some employee in the transaction
             approval hierarchy has been terminated. Please verify the approval
             hierarchy for terminated/inactive employees</li>
         <li>Source KB Article: [1073703.1]</li>
         </ul>',
            NULL,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');
      ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
           add_signature(
            'Note1073703.1',
            l_dynamic_SQL,
            'Document Manager error in authority_checks_setup:40:100
             ORA-01403 and authority_check:20 APIs',
            'RS',
            'Found transaction(s) with error in authority_checks_setup:40:100
             ORA-01403 and authority_check:20 APIs',
            '<ul>
         <li>Review version of package PO_EMPLOYEES_SV in column PO_EMPLOYEES_SV_VERSION above</li>
         <li>If less than 120.3.12010000.6 then apply {15924594}</li>
         <li>Otherwise (version is correct) some employee in the transaction
             approval hierarchy has been terminated. Please verify the approval
             hierarchy for terminated/inactive employees</li>
         <li>Source KB Article: [1073703.1]</li>
         </ul>',
            NULL,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');
            
      END IF;
    END IF;
   
   l_dynamic_SQL := '';
   
  -------------------------------------------
  -- Note 985937.1
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,
             prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
        /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_UTIL.update_doc_auth_status:''||
            ''10:-20160ORA-20160: Encountered an error while getting ''||
            ''the ORACLE user account for your concurrent request%''||
            ''ORA-06512: at "APPS.ALR_PO_REQUISITI_%_UAR%ORA-04088: error ''||
            ''during execution of trigger%''||
            ''po.plsql.PO_DOCUMENT_ACTION_UTIL.change_doc_auth_state:''||
            ''120:update_doc_auth_status not successful%''||
            ''po.plsql.PO_DOCUMENT_ACTION_AUTH.approve:20:''||
            ''change_doc_auth_state not successful%''||
            ''po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:110:''||
            ''unexpected error in action call%''';
            
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;       
            
            
            
  
  add_signature(
   'Note985937.1',
   l_dynamic_SQL,
   'Document Manager Error in update_doc_auth_status:10 ORA-04088',
   'RS',
   'Found transactions which have document manager errors caused by
    invalid trigger APPS.ALR_PO_REQUISITI_201_69780_UAR',
   '<ul><li>Deactivate the PO Document Approval Manager
    <ol>
<li>Start up the Sysadmin responsibility</li>
<li>Navigate to Concurrent -> Manager -> Administer</li>
<li>Query PO Document Approval Manager</li>
<li>Choose Terminate button</li></ol></li>
<li>Compile all invalid objects using ADADMIN</li>
<li>Relink the PO Doc Approval Manager executable using syntax
    below from the $PO_TOP/bin directory (this should be done
    during down time and the PO Document Approval Manager must
    be deactived first before relinking it.
<blockquote><pre>
cd $PO_TOP/bin
$ adrelink.sh force=y ranlib=y "PO POXCON"
</pre></blockquote> </li>
<li>Reactivate the PO Document Approval Manager
<ol>
<li>Start up the Sysadmin responsibility</li>
<li>Navigate to Concurrent -> Manager -> Administer</li>
<li>Query PO Document Approval Manager</li>
<li>Choose Activate button. </li></ol></li>
<li> Source KB Article: [985937.1]</li>
</ul>',
   null,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');

  -------------------------------------------
  -- Note 312582.1
  -------------------------------------------   
   
  add_signature(
   'Note312582.1_SINGLE',
   ' select recipient_role, subject from wf_notifications
     where status = ''OPEN''
     and message_type = ''POERROR''
     and message_name in (''DOC_MANAGER_FAILED_SYSADMIN'', ''DOC_MANAGER_FAILED'')
     and subject like ''%##$$DOCNUM$$##%''',
   'Document Manager error',
   'RS',
   'The transaction has failed with one of these errors: Doc Mgr Error 1 (Approval Manager Timeout) or Doc Mgr Error 2 (Document Approval Manager Not Active) or Doc Mgr Error 3 (Other exceptions in the Document Approval Manager code)',
   'Perform the following steps to retry the failed document:
    <ol>
     <li>Run wfretry.sql or the alternate wfretry documented in Note 134960.1 ‘Running WFSTATUS and WFRETRY For Oracle Purchasing Workflows’.</li>
     <li>If the retry does not resolve the issue then attempt the reset script from Note 390023.1 ‘How To Reset a Document From In-Process or Pre-Approved To Incomplete/Requires Reapproval For Isolated Cases’.</li>
    </ol>
    <br> Source KB Article: [312582.1]',
   null,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');
   
   
  -------------------------------------------
  -- Note 1097585.1
  -------------------------------------------   
   
  add_signature(
   'Note1097585.1',
   'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,prh.authorization_status) Authorization_Status
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:16:failed to lock document after 1000 tries''
    AND   NOT EXISTS (
               SELECT 1
               FROM fnd_profile_option_values povl
               WHERE povl.profile_option_id = 1266
               AND   ((povl.level_id = 10001) OR
                      (povl.level_id = 10002 AND
                       povl.level_Value = 201))
               AND   povl.profile_option_value is not null)
    AND poh.po_header_id = ##$$DOCID$$##
   ',
   'An approver has updated details in the PO Entry form',
   'RS',
   'One of the aprovers has updated the PO details in the PO Entry form through the ''Open Document'' link',
   'Review and follow the steps from [1097585.1] to correct such issues.',
   NULL,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y');      
   
   
   l_dynamic_SQL := '';

  -------------------------------------------
  -- Note 1317504.1
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT ''Purchase Order'' Transaction_Type,
           poh.segment1 Transaction_Number,
           poh.org_id Organization_Id,
           poh.authorization_status Authorization_Status,
           substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
             1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
             '' '',1,1)-1) Package_Version
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type = wiav.item_type
    AND   poh.wf_item_key = wiav.item_key
    AND   poh.authorization_status IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''po.plsql.PO_DOCUMENT_ACTION_CLOSE.auto_close_po:20:''||
            ''user id not found%''||
            ''po.plsql.PO_DOCUMENT_ACTION_PVT.do_action:110:''||
            ''unexpected error in action call''
    AND   ((''12.1'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.32.12010000.28'') = ''<'' ) OR
           (''12.0'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                '' '',1,1)-1),
              ''120.21.12000000.34'') = ''<'' ))
    AND   als.type = ''PACKAGE BODY''

    AND   als.name = ''FND_GLOBAL''
    AND   als.text like ''%$Header%''';
    
    
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) AND (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
       l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
   END IF;
  
   IF (g_sql_tokens('##$$REL$$##') IS NOT NULL) THEN
      IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') THEN
           add_signature(
            'Note1317504.1',
            l_dynamic_SQL,
            'Purchase Orders Stuck with "user id not found" Errors in auto_close_po:20',
            'RS',
            'Found transactions with "user id not found" errors at
             PO_DOCUMENT_ACTION_CLOSE.auto_close_po:20 and FND_GLOBAL version is
             less than 120.21.12000000.34',
            '<ul>
         <li>Solution:
         <ol>
         <li>Download and review the readme and pre-requisites for {10202933}</li>
         <li>Confirm the following file version: AFSCGBLB.pls - 120.21.12000000.34</li>
         <li>Retest the issue.</li>
         <li>Source KB Article: [1317504.1]</li>
         </ul>',
            null,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');
      ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
           add_signature(
            'Note1317504.1',
            l_dynamic_SQL,
            'Purchase Orders Stuck with "user id not found" Errors in auto_close_po:20',
            'RS',
            'Found transactions with "user id not found" errors at
             PO_DOCUMENT_ACTION_CLOSE.auto_close_po:20 and FND_GLOBAL version is
             less than 120.32.12010000.28',
            '<ul>
         <li>Solution:
         <ol>
         <li>Download and review the readme and pre-requisites for {11869611}</li>
         <li>Confirm the following file version: AFSCGBLB.pls 120.32.12010000.28</li>
         <li>Retest the issue.</li>
         <li>Source KB Article: [1317504.1]</li>
         </ul>',
            null,
            'FAILURE',
            'E',
            p_include_in_dx_summary => 'Y');
      END IF;      
   END IF;  
  
  

   l_dynamic_SQL := '';

  -------------------------------------------
  -- Note 1370218.1
  -------------------------------------------
  
  l_dynamic_SQL := 'SELECT decode(nvl(poh.segment1,''$$$''),''$$$'',
             decode(nvl(prh.segment1,''$$$''),''$$$'',''Unknown'',
               ''Requisition''),
             ''Purchase Order'') Transaction_Type,
           nvl(poh.segment1,prh.segment1) Transaction_Number,
           nvl(poh.org_id,prh.org_id) Organization_Id,
           nvl(poh.authorization_status,
             prh.authorization_status) Authorization_Status,
           substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
             1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
             '' '',1,1)-1) Package_Version
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia,
         wf_items wfi,
         wf_notifications wfn,
         po_headers_all poh,
         po_requisition_headers_all prh,
         all_source als
    WHERE wiav.item_type in (''REQAPPRV'', ''POAPPRV'')
    AND   wia.item_type = wiav.item_type
    AND   wia.name = wiav.name
    AND   wiav.name = ''SYSADMIN_ERROR_MSG''
    AND   wia.type <> ''EVENT''
    AND   wiav.item_key = wfi.parent_item_key
    AND   wfi.item_type = ''POERROR''
    AND   wfi.item_key = wfn.item_key
    AND   wfn.status = ''OPEN''
    AND   wfn.message_type = ''POERROR''
    AND   wfn.message_name = ''DOC_MANAGER_FAILED''
    AND   poh.wf_item_type(+) = wiav.item_type
    AND   poh.wf_item_key(+) = wiav.item_key
    AND   prh.wf_item_type(+) = wiav.item_type
    AND   prh.wf_item_key(+) = wiav.item_key
    AND   nvl(poh.authorization_status,prh.authorization_status) IN (
            ''IN PROCESS'', ''PRE-APPROVED'')
       /* Base script ends, specific checks for this error follow */
    AND   wiav.text_value like
            ''Unexpected error occurred during Tax Calculation.%''||
            ''Exception: 023 - An unexpected error has occurred%''||
            ''Please contact your system administrator.%''
    AND   ((''12.1'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1) - 1),
                '' '',1,1)-1),
              ''120.246.12010000.58'') = ''<'' ) OR
           (''12.0'' = substr(''##$$REL$$##'',1,4) AND
            FND_IREP_LOADER_PRIVATE.compare_versions(
              substr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                1, instr(substr(als.text,regexp_instr(als.text,''  *[0-9]'',1,1,1)-1),
                '' '',1,1)-1),
              ''120.230.12000000.99'') = ''<'' ))
    AND   als.type = ''PACKAGE BODY''
    AND   als.name = ''ZX_SRVC_TYP_PKG''
    AND   als.text like ''%$Header%''';
 
   IF (g_sql_tokens('##$$DOCNUM$$##') IS NOT NULL) THEN
       IF (g_sql_tokens('##$$TRXTP$$##') = 'PO') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND poh.po_header_id = ##$$DOCID$$##';
       ELSIF  (g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION') THEN
              l_dynamic_SQL := l_dynamic_SQL || ' AND prh.requisition_header_id = ##$$DOCID$$##';
       END IF;
   END IF;   
 
   IF (g_sql_tokens('##$$REL$$##') IS NOT NULL) THEN
      IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') THEN
            add_signature(
             'Note1370218.1',
             l_dynamic_SQL,
             'Unexpected Error During Tax Calculation',
             'RS',
             'Found transactions which are stuck due to errors in Tax Calculation
              and which have versions of zxifsrvctypspkgb.pls less than
              120.230.12000000.99',
             '<ul>
          <li>Upgrade to a higher version of zxifsrvctypspkgb.pls. There are various
              causes of this error resolved in higher versions of this file.</li>
          <li>Download and apply {14589356} which contains version:<ul>
             <li> zxifsrvctypspkgb.pls 120.230.12000000.114 </li>
          <li>Lastly review the data integrity section of this report to see if errors
              with "Incorrect Tax Attribute Update Code" are present, as this issue
              can be a result of that data corruption as well.</li>
          <li>Source KB Article: [1370218.1]</li>
          </ul>',
             null,
             'FAILURE',
             'E',
             p_include_in_dx_summary => 'Y');
      ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
            add_signature(
             'Note1370218.1',
             l_dynamic_SQL,
             'Unexpected Error During Tax Calculation',
             'RS',
             'Found transactions which are stuck due to errors in Tax Calculation
              and which have versions of zxifsrvctypspkgb.pls less than
              120.246.12010000.58',
             '<ul>
          <li>Upgrade to a higher version of zxifsrvctypspkgb.pls. There are various
              causes of this error resolved in higher versions of this file.</li>
          <li>Down load and apply {14589356} which contains version:<ul>
             <li> zxifsrvctypspkgb.pls 120.246.12010000.73 </li></ul></li>
          <li>It is also recommended that you apply
              {14277162} R12.1: E-Business Tax Recommended Patch Collection (ZX),
              August 2012</li>
          <li>Lastly review the data integrity section of this report to see if errors
              with "Incorrect Tax Attribute Update Code" are present, as this issue
              can be a result of that data corruption as well.</li>
          <li>Source KB Article: [1370218.1]</li>
          </ul>',
             null,
             'FAILURE',
             'E',
             p_include_in_dx_summary => 'Y');      
      END IF;
   END IF;
 
  -------------------------------------------
  -- Note 312582.1
  -------------------------------------------   
  
  add_signature(
   'Note312582.1_ALL',
   ' select recipient_role, subject from wf_notifications
     where status = ''OPEN''
     and message_type = ''POERROR''
     and message_name in (''DOC_MANAGER_FAILED_SYSADMIN'', ''DOC_MANAGER_FAILED'')
     and begin_date >= to_date(''##$$FDATE$$##'')',
   'Document Manager error',
   'RS',
   'Some transactions have failed with one of these errors: Doc Mgr Error 1 (Approval Manager Timeout) or Doc Mgr Error 2 (Document Approval Manager Not Active) or Doc Mgr Error 3 (Other exceptions in the Document Approval Manager code)',
   'Perform the following steps to retry the failed document:
    <ol>
     <li>Run wfretry.sql or the alternate wfretry documented in Note 134960.1 ‘Running WFSTATUS and WFRETRY For Oracle Purchasing Workflows’.</li>
     <li>If the retry does not resolve the issue then attempt the reset script from Note 390023.1 ‘How To Reset a Document From In-Process or Pre-Approved To Incomplete/Requires Reapproval For Isolated Cases’.</li>
    </ol>
    <br> Source KB Article: [312582.1]',
   null,
   'FAILURE',
   'E',
   p_include_in_dx_summary => 'Y') ;
 

   l_dynamic_SQL := '';

/*############################################
  # D o c u m e n t  R e s e t  S i g s      #
  ############################################*/

  -------------------------------------------
  -- Note 390023.1 Generic Case 1
  -------------------------------------------

  l_info.delete;
  l_info('Doc ID') := '390023.1';
  l_info('Bug Number') := '9707155';

  add_signature(
   'Note390023.1_case_GEN1',
   'SELECT count(*)
    FROM (
         SELECT bug_number FROM ad_bugs
         UNION
         SELECT patch_name FROM ad_applied_patches
       ) bugs
    WHERE bugs.bug_number like ''9707155''',
    'Reset Patch Not Applied',
    '[count(*)] = [0]',
    'The patch for resetting a document has not been applied',
    'In order to reset stuck documents you will need to apply {9707155} '||
      'which contains the requires data fix scripts',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Generic Case 2
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1487949.1';
  l_info('Bug Number') := '14254641';

  add_signature(
   'Note390023.1_case_GEN2',
   'SELECT count(*)
    FROM (
           SELECT 1
           FROM (
                  SELECT bug_number FROM ad_bugs
                  UNION
                  SELECT patch_name FROM ad_applied_patches
                ) bugs
           WHERE bugs.bug_number = ''14254641''
           AND   ''##$$REL$$##'' = ''12.1.3''
           UNION
           SELECT 1 FROM dual WHERE ''##$$REL$$##'' like ''12.2%''
         )',
    'Availability of Withdrawal Functionality for Purchase Orders',
    '[count(*)] = [0]',
    'Standard withdrawal functionality for Purchase Orders
     is not available on this code level',
    'In order to use standard document withdrawal functionality
     for Purchase Orders, you must be on at least release 12.1.3
     with rollup {14254641}:R12.PRC_PF.B applied.',
    'Standard withdrawal functionality for Purchase Orders
     is available within the product on this code level.
     You should review [1487949.1] and consider using the
     standard functionality to reset PO documents if needed.',
    'ALWAYS',
    'I',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Generic Case 3
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1487949.1';
  l_info('Bug Number') := '14254641';

  add_signature(
   'Note390023.1_case_GEN3',
   'SELECT count(*)
    FROM fnd_product_installations
    WHERE application_id = 178
    AND   status = ''I''',
    'Availability of Withdrawal Functionality for Requisitions',
    '[count(*)] = [0]',
    'Standard withdrawal functionality for Requisitions
     is not available.',
    'In order to use standard document withdrawal functionality
     for Requisitions, you must have iProcurement installed.',
    'Standard withdrawal functionality for Requisitions is
     available within the product.  You should review [1519850.1]
     and consider using the standard functionality to reset
     Requisition documents if needed.',
    'ALWAYS',
    'I',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO1
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO1',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       h.change_requested_by,
       h.po_header_id, h.segment1,
       h.revision_num, h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   h.authorization_status NOT IN (''IN PROCESS'', ''PRE-APPROVED'')',
    'Document Eligibility for Reset',
    'RS',
    'This document is not in a status requiring reset.',
    'No further action is require with regards to resetting this document.
     Only documents with authorization_status ''IN PROCESS'' or ''PRE-APPROVED''
     are eligible to be reset.',
    null,
    'FAILURE',
    'W',
    'Y',
    'Y',

    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO2
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO2',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       h.change_requested_by,
       h.po_header_id, h.segment1,
       h.revision_num, h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    '[canceled]<>[N]',
    'This document is canceled. It is not eligible to reset.',
    'No further action is require with regards to resetting this document
     canceled documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'Y',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO3
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO3',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       h.change_requested_by,
       h.po_header_id, h.segment1,
       h.revision_num, h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    '[closed_code]=[FINALLY CLOSED]',
    'This document is FINALLY CLOSED. It is not eligible to reset.',
    'No further action is require with regards to resetting this document.
     Canceled documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'Y',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO4
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO4',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       h.change_requested_by,
       h.po_header_id, h.segment1,
       h.revision_num, h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   h.change_requested_by IN (''REQUESTER'',''SUPPLIER'')',
    'Document Eligibility for Reset',
    'RS',
    'This document is associated with a change request. It is not eligible to reset.',
    'There is an open change request against this PO document. You should process
     any change request notifications.',
    null,
    'FAILURE',
    'W',
    'Y',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO4.1
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO4.1',
   'SELECT cr.change_request_id, cr.initiator,
           cr.action_type, cr.request_status,
           cr.wf_item_type, cr.wf_item_key,
           n.subject "Notification Subject",
           ias.assigned_user "Notif Assigned",
           n.to_user "Notif User"
    FROM wf_item_activity_statuses ias,
         wf_notifications          n,
         po_change_requests        cr
    WHERE ias.notification_id = n.group_id (+)
    AND   n.status (+) = ''OPEN''
    AND   ias.item_type (+) = cr.wf_item_type
    AND   ias.item_key (+) = cr.wf_item_key
    AND   cr.change_active_flag = ''Y''
    AND   cr.document_type = ''PO''
    AND   cr.document_header_id = ##$$DOCID$$##',
    'Open Change Requests',
    'NRS',
    null,
    null,
    'This document is associated with an open change request.
     Review the details of the open requests and any pending workflow
     notifications above and process these in order to progress
     this document.',
    'SUCCESS',
    'I',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO5
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO5',
   'SELECT h.wf_item_type, h.wf_item_key po_wf_item_key,
           ias.item_key notification_item_key,
           ias.assigned_user, n.to_user, n.subject,
           n.status
    FROM wf_item_activity_statuses ias,
         wf_notifications n,
         po_headers_all h
    WHERE ias.notification_id is not null
    AND   ias.notification_id = n.group_id
    AND   n.status = ''OPEN''
    AND   h.po_header_id = ##$$DOCID$$##
    AND   h.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
    AND   ias.item_type = ''POAPPRV''
    AND   ias.item_key IN (
            SELECT i.item_key
            FROM wf_items i
            START WITH i.item_type = h.wf_item_type
            AND   i.item_key = h.wf_item_key
            CONNECT BY PRIOR i.item_type = i.parent_item_type
            AND   PRIOR i.item_key = i.parent_item_key
            AND   nvl(i.end_date, sysdate+1) >= sysdate)',
    'Open Notifications for Document',
    'RS',
    'This document has an open approval workflow notification.
     To progress this document you should process this notification
     via the application rather than resetting the document.',
    'Review notification details listed and insure the responsible
     party processes the open notification for the document.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO6
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO6',
   'SELECT ''Wrong Encumbrance Amount''
    FROM dual
    WHERE EXISTS (
        SELECT 1
        FROM po_headers_all h,
             po_lines_all l,
             po_line_locations_all s,
             po_distributions_all d
        WHERE  s.line_location_id = d.line_location_id
        AND   l.po_line_id = s.po_line_id
        AND   h.po_header_id = ##$$DOCID$$##
        AND   d.po_header_id = h.po_header_id
        AND   l.matching_basis = ''QUANTITY''
        AND   nvl(d.encumbered_flag, ''N'') = ''Y''
        AND   nvl(s.cancel_flag, ''N'') = ''N''
        AND   nvl(s.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
        AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
        AND   d.budget_account_id IS NOT NULL
        AND   nvl(s.shipment_type,''BLANKET'') = ''STANDARD''
        AND   round(nvl(d.encumbered_amount, 0), 2) <>
                round((s.price_override * d.quantity_ordered *
                nvl(d.rate, 1) + nvl(d.nonrecoverable_tax, 0) *
                nvl(d.rate, 1)), 2)
        UNION
        SELECT 1
        FROM po_headers_all h,
             po_lines_all l,
             po_line_locations_all s,
             po_distributions_all d
        WHERE  s.line_location_id = d.line_location_id
        AND   l.po_line_id = s.po_line_id
        AND   h.po_header_id = d.po_header_id
        AND   d.po_header_id = ##$$DOCID$$##
        AND   l.matching_basis = ''AMOUNT''
        AND   nvl(d.encumbered_flag, ''N'') = ''Y''
        AND   nvl(s.cancel_flag, ''N'') = ''N''
        AND   nvl(s.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
        AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
        AND   d.budget_account_id IS NOT NULL
        AND   nvl(s.shipment_type,''BLANKET'') = ''STANDARD''
        AND   round(nvl(d.encumbered_amount, 0), 2) <>
                round((d.amount_ordered +
                nvl(d.nonrecoverable_tax, 0)) *
                nvl(d.rate, 1), 2))',
    'Encumbrance Amount Validation',
    'RS',
    'This Standard PO has at least one distribution with an incorrect encumbrance
     amount.  The document reset scripts cannot be run against this document.',
    'To reset this document you would need to create a Service Request with
     customer support.',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO7
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO7',
   'SELECT ''Encumbered distribution with PLANNED shipment type''
           fail_cause
    FROM dual
    WHERE EXISTS (
            SELECT 1
            FROM po_headers_all h,
                 po_lines_all l,
                 po_line_locations_all s,
                 po_distributions_all d
            WHERE  s.line_location_id = d.line_location_id
            AND   l.po_line_id = s.po_line_id
            AND   h.po_header_id = d.po_header_id
            AND   d.po_header_id = ##$$DOCID$$##
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   nvl(s.shipment_type,''BLANKET'') = ''PLANNED'')',
    'Encumbered Distribution with PLANNED Shipment Type',
    'RS',
    'This Planned PO has at least one encumbered distribution. The
     document reset scripts cannot be applied to this document.',
    'In order to reset this document you would have to create a Service
     Request with customer support.',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO8
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO8',
   'SELECT ''Blanket Purchase Agreement with Encumbrance Required''
           fail_cause
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   nvl(h.ENCUMBRANCE_REQUIRED_FLAG, ''N'') = ''Y''
    AND   h.type_lookup_code = ''BLANKET''',
    'Blanket PO With Encumberance Required.',
    'RS',
    'This Blanket PO has encumbrance required.  The document rest
     scripts cannot be applied to this document.',
    'In order to reset this document you would have to create a Service
     Request with customer support.',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case PO9
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_PO9',
   'SELECT ''poxrespo.sql'' "Script Name",
           h.segment1 "PO Number",
           h.org_id "Organization ID",
           h.authorization_status,
           nvl(h.cancel_flag,''N'') canceled,
           nvl(h.closed_code,''OPEN'') closed_code,
           h.change_requested_by,
           h.po_header_id, h.segment1,
           h.revision_num, h.type_lookup_code,
           h.wf_item_type, h.wf_item_key,
           h.approved_date
    FROM po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    'NRS',
    null,
    null,
    'This document is not cancelled or finally closed, the authorization
     status is either IN PROCESS or PRE-APPROVED, and it is not associated
     with a change request. It does not have open notifications, nor any
     issues with encumbrance that would prevent using the reset scripts.
     It meets all the requirements of a PO document to be reset.<br/><br/>
     To reset the document:
     <ul>
      <li>Use the script indicated above from {9707155}. This file should be
          located in $PO_TOP/sql directory on your server.</li>
      <li>The script will prompt for the PO Number and organization id.
          These values are also provided above.</li>
      <li>You will also be asked if you wish to delete the action history
          for the unsuccessful approval cycle. Enter Y if you wish to
          delete this history, or N if not.  The standard practice
          is to select N for this option</li><ul>',
    'SUCCESS',
    'I',
    'Y',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  -------------------------------------------
  -- Note 390023.1 Case PO10
  -------------------------------------------
  add_signature(
   'Note390023.1_case_PO10',
   'SELECT ah.sequence_num,
           ah.action_date,
           ah.action_code,
           ph.authorization_status,
           p.full_name,
           ah.employee_id,
           ph.segment1 po_num,
           ah.object_revision_num rev_num,
           ah.approval_path_id,
           ah.note,
           ah.last_update_date,
           ah.last_updated_by,
           ah.creation_date,
           ah.created_by
    FROM po_headers_all ph,
         po_action_history ah,
         per_all_people_f p
    WHERE ah.object_id = ph.po_header_id
    AND   p.person_id (+) = ah.employee_id
    AND   sysdate BETWEEN
            p.effective_start_date(+) AND p.effective_end_date (+)
    AND   ah.object_type_code in (''PO'', ''PA'')
    AND   ah.object_id = ##$$DOCID$$##
    ORDER BY ah.sequence_num',
   'Document Action History',
   'NRS',
   null,
   null,
   null,
   'SUCCESS',
   'I',
   'RS',
   'Y');
  
  -------------------------------------------
  -- Note 1565821.1
  -------------------------------------------
  add_signature(
   'Note1565821.1',
   'select  to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
            to_char(ias.end_date,''DD-MON-RR HH24:MI:SS'') end_date,
            ap.name||''/''||pa.instance_label Activity,
            ias.activity_status Status,
            ias.activity_result_code Result,
            ias.assigned_user assigned_user,
            ias.notification_id NID,
            ntf.status "Status",
            ias.action,
            ias.performed_by
    from    wf_item_activity_statuses ias,
            wf_process_activities pa,
            wf_activities ac,
            wf_activities ap,
            wf_items i,
            wf_notifications ntf,
            po_headers_all poh
    where   ias.item_type = ''POAPPRV''
    and     ias.process_activity    = pa.instance_id
    and     pa.activity_name        = ac.name
    and     pa.activity_item_type   = ac.item_type
    and     pa.process_name         = ap.name
    and     ias.activity_result_code like ''%NO_NEXT_APPROVER%''
    and     pa.process_item_type    = ap.item_type
    and     pa.process_version      = ap.version
    and     i.item_type             = ''POAPPRV''
    and     i.item_key              = ''##$$ITMKEY$$##''
    and     i.item_key              = ias.item_key
    and     ias.item_key            = poh.wf_item_key
    and     ias.item_type           = poh.wf_item_type
    and     poh.authorization_status = ''APPROVED''
    and     i.begin_date            >= ac.begin_date
    and     i.begin_date            < nvl(ac.end_date, i.begin_date+1)
    and     ntf.notification_id(+)  = ias.notification_id',
   'Document Approved without Authority',
   'RS',
   'The revised document is approved without any authorization because the value of Workflow Attribute AME_APPROVAL_ID is not being updated with a new value',
   'Please review [1565821.1] for more details on this issue and the steps to fix this problem.',
   null,
   'FAILURE',
   'W',
   'N',
   'Y');   

  -------------------------------------------
  -- Note 390023.1 Case REQ1
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ1',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       nvl(h.transferred_to_oe_flag,''N'') transferred_to_oe,
       h.requisition_header_id, h.segment1,
       h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_requisition_headers_all h
    WHERE h.requisition_header_id = ##$$DOCID$$##
    AND   h.authorization_status NOT IN (''IN PROCESS'', ''PRE-APPROVED'')',
    'Document Eligibility for Reset',
    'RS',
    'This document is not in a status requiring reset.',
    'No further action is require with regards to resetting this document.
     Only documents with authorization_status ''IN PROCESS'' or ''PRE-APPROVED''
     are eligible to be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ2
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ2',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       nvl(h.transferred_to_oe_flag,''N'') transferred_to_oe,
       h.requisition_header_id, h.segment1,
       h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_requisition_headers_all h
    WHERE h.requisition_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    '[canceled]<>[N]',
    'This document is canceled. It is not eligible to reset.',
    'No further action is require with regards to resetting this document.
     Canceled documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ3
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ3',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       nvl(h.transferred_to_oe_flag,''N'') transferred_to_oe,
       h.requisition_header_id, h.segment1,
       h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_requisition_headers_all h
    WHERE h.requisition_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    '[closed_code]=[FINALLY CLOSED]',
    'This document is FINALLY CLOSED. It is not eligible to reset.',
    'No further action is require with regards to resetting this document.
     Finally closed documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ4
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ4',
   'SELECT h.authorization_status,
       nvl(h.cancel_flag,''N'') canceled,
       nvl(h.closed_code,''OPEN'') closed_code,
       nvl(h.transferred_to_oe_flag,''N'') transferred_to_oe,
       h.requisition_header_id, h.segment1,
       h.type_lookup_code,
       h.wf_item_type, h.wf_item_key,
       h.approved_date
    FROM po_requisition_headers_all h
    WHERE h.requisition_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    '[transferred_to_oe]=[Y]',
    'This document is associated with a sales order. It is not eligible to reset.',
    'No further action is require with regards to resetting this document
     requisition documents associated with sales orders cannot be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ5
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ5',
   'SELECT count(*)
    FROM po_requisition_lines_all rl,
         po_requisition_headers_all rh
    WHERE rh.requisition_header_id = ##$$DOCID$$##
    AND   rh.requisition_header_id = rl.requisition_header_id
    AND   rl.line_location_id is not null',
    'Document Eligibility for Reset',
    '[count(*)]>[0]',
    'This requisition is associated with a purchase order. It is not eligible to reset.',
    'No further action is require with regards to resetting this document
     requisition documents associated with purchase orders cannot be reset.',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ6
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ6',
   'SELECT rh.wf_item_type, rh.wf_item_key req_wf_item_key,
           ias.item_key notification_item_key,
           ias.assigned_user, n.to_user, n.subject

    FROM wf_item_activity_statuses ias,
         wf_notifications n,
         po_requisition_headers_all rh
    WHERE ias.notification_id is not null
    AND   ias.notification_id = n.group_id
    AND   n.status = ''OPEN''
    AND   rh.requisition_header_id = ##$$DOCID$$##
    AND   rh.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
    AND   ias.item_type = ''REQAPPRV''
    AND   ias.item_key IN (
            SELECT i.item_key
            FROM wf_items i
            START WITH i.item_type = rh.wf_item_type
            AND   i.item_key = rh.wf_item_key
            CONNECT BY PRIOR i.item_type = i.parent_item_type
            AND   PRIOR i.item_key = i.parent_item_key
            AND   nvl(i.end_date, sysdate+1) >= sysdate)',
    'Open Notifications for Document',
    'RS',
    'This document has an open approval workflow notification.
     To progress this document you should process this notification
     via the application rather than resetting the document.',
    'Review notification details listed and insure the responsible
     party processes the open notification for the document.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ7
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  l_info('Bug Number') := '9707155';
  add_signature(
   'Note390023.1_case_REQ7',
   'SELECT ''Wrong Encumbrance Amount''
    FROM dual
    WHERE EXISTS (
            SELECT 1
            FROM po_requisition_lines_all l,
                 po_req_distributions_all d
            WHERE l.requisition_header_id = ##$$DOCID$$##
            AND   d.requisition_line_id = l.requisition_line_id
            AND   l.matching_basis = ''QUANTITY''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(l.cancel_flag, ''N'') = ''N''
            AND   nvl(l.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round(l.unit_price * d.req_line_quantity +
                    nvl(d.nonrecoverable_tax, 0), 2)
            UNION
            SELECT 1
            FROM po_requisition_lines_all l,
                 po_req_distributions_all d
            WHERE l.requisition_header_id = ##$$DOCID$$##
            AND   d.requisition_line_id = l.requisition_line_id
            AND   l.matching_basis = ''AMOUNT''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(l.cancel_flag, ''N'') = ''N''
            AND   nvl(l.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round(d.req_line_amount +
                    nvl(d.nonrecoverable_tax, 0), 2))',
    'Encumbrance Amount Validation',
    'RS',
    'This requisition has at least one distribution with an incorrect encumbrance
     amount.  The document reset scripts cannot be run against this document.',
    'To reset this document you would need to create a Service Request with
     customer support.',
    null,
    'FAILURE',
    'W',
    'N',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REQ8
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REQ8',
   'SELECT ''poresreq.sql'' "Script Name",
           h.segment1 "Requisition Number",
           h.org_id "Organization ID",
           h.authorization_status,
           nvl(h.cancel_flag,''N'') canceled,
           nvl(h.closed_code,''OPEN'') closed_code,
           nvl(h.transferred_to_oe_flag,''N'') transferred_to_oe,
           h.requisition_header_id, h.segment1,
           h.type_lookup_code,
           h.wf_item_type, h.wf_item_key,
           h.approved_date
    FROM po_requisition_headers_all h
    WHERE h.requisition_header_id = ##$$DOCID$$##',
    'Document Eligibility for Reset',
    'NRS',
    null,
    null,
    'This document is not cancelled or finally closed, the authorization
     status is either IN PROCESS or PRE-APPROVED, and it is not associated
     with a sales order or a PO.  There are no open approval notifications
     for it and encumbrance amounts have been validated. It meets all the
     requirements of a requisition document to be reset<br/><br/>
     To reset this document: <ul>
     <li>Use the script indicated above from {9707155}.  This script should be
       located in $PO_TOP/sql on your server.</li>
     <li>The script will prompt you for the requisition number and organization
       id.  These have also been displayed above.</li></ul>',
    'SUCCESS',
    'I',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  -------------------------------------------
  -- Note 390023.1 Case REQ9
  -------------------------------------------
  add_signature(
   'Note390023.1_case_REQ9',
   'SELECT ah.sequence_num,
           ah.action_date,
           ah.action_code,
           rh.authorization_status,
           p.full_name,
           ah.employee_id,
           rh.segment1 req_num,
           ah.object_revision_num rev_num,
           ah.approval_path_id,
           ah.note,
           ah.last_update_date,
           ah.last_updated_by,
           ah.creation_date,
           ah.created_by
    FROM po_requisition_headers_all rh,
         po_action_history ah,
         per_people_f p
    WHERE ah.object_id = rh.requisition_header_id
    AND   p.person_id (+) = ah.employee_id
    AND   sysdate BETWEEN
            p.effective_start_date(+) AND p.effective_end_date (+)
    AND   ah.object_type_code = ''REQUISITION''
    AND   ah.object_id = ##$$DOCID$$##
    ORDER BY ah.sequence_num',
    'Document Action History',
    'NRS',
    null,
    null,
    'Action history for the document.',
    'SUCCESS',
    'I',
    'RS',
    'Y');

  -------------------------------------------
  -- Note 390023.1 Case REL1
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL1',
   'SELECT r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.po_header_id, h.segment1 po_number,
           r.po_release_id,
           r.release_num, r.release_type,
           r.revision_num,
           r.wf_item_type, r.wf_item_key
    FROM po_headers_all h,
         po_releases_all r
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.org_id = h.org_id
    AND   r.po_header_id = h.po_header_id
    AND   r.authorization_status NOT IN (''IN PROCESS'',''PRE-APPROVED'')',
    'Document Eligibility for Reset',
    'RS',
    'This document is not in a status requiring reset.',
    'No further action is require with regards to resetting this document.
     Only documents with authorization_status ''IN PROCESS'' or ''PRE-APPROVED''
     are eligible to be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL2
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL2',
   'SELECT r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.po_header_id, h.segment1 po_number,
           r.po_release_id,
           r.release_num, r.release_type,
           r.revision_num,
           r.wf_item_type, r.wf_item_key
    FROM po_headers_all h,
         po_releases_all r
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.org_id = h.org_id
    AND   r.po_header_id = h.po_header_id',
    'Document Eligibility for Reset',
    '[canceled]<>[N]',
    'This document is canceled. It is not eligible to reset.',
    'No further action is require with regards to resetting this document.
     Canceled documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL3
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL3',
   'SELECT r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.po_header_id, h.segment1 po_number,
           r.po_release_id,
           r.release_num, r.release_type,
           r.revision_num,
           r.wf_item_type, r.wf_item_key
    FROM po_headers_all h,
         po_releases_all r
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.org_id = h.org_id
    AND   r.po_header_id = h.po_header_id',
    'Document Eligibility for Reset',
    '[closed_code]=[FINALLY CLOSED]',
    'This document is FINALLY CLOSED. It is not eligible to reset.',
    'No further action is require with regards to resetting this document.
     Finally closed documents cannot be reset.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL4
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL4',
   'SELECT r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.po_header_id, h.segment1 po_number,
           r.po_release_id,
           r.release_num, r.release_type,
           r.revision_num,
           r.wf_item_type, r.wf_item_key
    FROM po_headers_all h,
         po_releases_all r
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.org_id = h.org_id
    AND   r.po_header_id = h.po_header_id
    AND   r.change_requested_by IN (''REQUESTER'',''SUPPLIER'')',
    'Document Eligibility for Reset',
    'RS',
    'This document is associated with a change request. It is not eligible to reset.',
    'There is an an open change request against this PO release document. You
     should process any change request notifications.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL4.1
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL4.1',
   'SELECT cr.change_request_id, cr.initiator,
           cr.action_type, cr.request_status,
           cr.wf_item_type, cr.wf_item_key,
           n.subject "Notification Subject",
           ias.assigned_user "Notif Assigned",
           n.to_user "Notif User"
    FROM wf_item_activity_statuses ias,
         wf_notifications          n,
         po_change_requests        cr
    WHERE ias.notification_id = n.group_id (+)
    AND   n.status (+) = ''OPEN''
    AND   ias.item_type (+) = cr.wf_item_type
    AND   ias.item_key (+) = cr.wf_item_key
    AND   cr.change_active_flag = ''Y''
    AND   cr.document_type = ''RELEASE''
    AND   cr.document_header_id = ##$$DOCID$$##
    AND   cr.po_release_id = ##$$RELID$$##',
    'Open Change Requests',
    'NRS',
    null,
    null,
    'This document is associated with an open change request.
     Review the details of the open requests and any pending workflow
     notifications above and process these in order to progress
     this document.',
    'SUCCESS',
    'I',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL5
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL5',
   'SELECT r.wf_item_type, r.wf_item_key,
           ias.assigned_user, n.to_user, n.subject
    FROM wf_item_activity_statuses ias,
         wf_notifications          n,
         po_releases_all           r
    WHERE ias.notification_id is not null
    AND   ias.notification_id = n.group_id
    AND   n.status = ''OPEN''
    AND   ias.item_type = ''POAPPRV''
    AND   ias.item_key = r.wf_item_key
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.authorization_status IN
            (''IN PROCESS'', ''PRE-APPROVED'')',
    'Open Notifications for Document',
    'RS',
    'This document has an open approval workflow notification.
     To progress this document you should process this notification
     via the application rather than resetting the document.',
    'Review notification details listed and insure the responsible
     party processes the open notification for the document.',
    null,
    'FAILURE',
    'W',
    'RS',
    'Y',
    l_info);

  -------------------------------------------
  -- Note 390023.1 Case REL6
  -------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '390023.1';
  add_signature(
   'Note390023.1_case_REL6',
   'SELECT ''poresrel.sql'' "Script Name",
           h.segment1 "PO Number",
           r.release_num "Release Num",
           h.org_id "Organization ID",
           r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.po_header_id, r.po_release_id,
           r.release_type, r.revision_num,
           r.wf_item_type, r.wf_item_key
    FROM po_headers_all h,
         po_releases_all r
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   r.po_release_id = ##$$RELID$$##
    AND   r.org_id = h.org_id
    AND   r.po_header_id = h.po_header_id',
    'Document Eligibility for Reset',
    'NRS',
    null,
    null,
    'This document is not cancelled or finally closed, the authorization
     status is either IN PROCESS or PRE-APPROVED, it is not associated
     with a change request, and there are no open approval notifications
     for it. It meets all the requirements of a release document to
     be reset<br/><br/>
     To reset this document: <ul>
     <li>Use the script indicated above from {9707155}.  This script should be
       located in $PO_TOP/sql on your server.</li>
     <li>The script will prompt you for the PO number, release number,
       and organization id.  These values have also been displayed above.</li>
      <li>You will also be asked if you wish to delete the action history
          for the unsuccessful approval cycle. Enter Y if you wish to
          delete this history, or N if not.  The standard practice
          is to select N for this option</li><ul>',
    'SUCCESS',
    'I',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  -------------------------------------------
  -- Note 390023.1 Case REL7
  -------------------------------------------
  add_signature(
   'Note390023.1_case_REL7',
   'SELECT ah.sequence_num,
           ah.action_date,
           ah.action_code,
           r.authorization_status,
           p.full_name,
           ah.employee_id,
           h.segment1 po_num,
           r.release_num,
           ah.object_revision_num rev_num,
           ah.approval_path_id,
           ah.note,
           ah.last_update_date,
           ah.last_updated_by,
           ah.creation_date,
           ah.created_by
    FROM po_releases_all r,
         po_headers_all h,
         po_action_history ah,
         per_people_f p
    WHERE ah.object_id = r.po_release_id
    AND   h.po_header_id = r.po_header_id
    AND   p.person_id (+) = ah.employee_id
    AND   sysdate BETWEEN
            p.effective_start_date(+) AND p.effective_end_date (+)
    AND   ah.object_type_code = ''RELEASE''
    AND   ah.object_id = ##$$RELID$$##
    ORDER BY ah.sequence_num',
   'Document Action History',
   'NRS',
   null,
   null,
   'Action history for the document.',
   'SUCCESS',
   'I',
   'RS',
   'Y');

  -------------------------------------------
  -- Note 390023.1 General Case 4
  -------------------------------------------
  l_info.delete;
  add_signature(
   'Note390023.1_case_GEN4',
   'SELECT ''PO/PA'' "Doc Type",
           h.segment1 "Doc Number",
           h.po_header_id "Doc ID",
           h.org_id,
           null "Release Num",
           null "PO Release ID",
           h.type_lookup_code "Type Code",
           h.authorization_status "Athorization Status",
           nvl(h.cancel_flag,''N'') canceled,
           nvl(h.closed_code,''OPEN'') "Closed Code",
           h.change_requested_by "Change Requested By",
           h.revision_num,
           h.wf_item_type, h.wf_item_type "##$$FK1$$##",
           h.wf_item_key, h.wf_item_key "##$$FK2$$##",
           h.approved_date "Approved Date"
    FROM po_headers_all h
    WHERE to_date(''##$$FDATE$$##'') <= (
            SELECT max(ah.action_date) FROM po_action_history ah
            WHERE ah.object_id = h.po_header_id
            AND   ah.object_type_code IN (''PO'',''PA'')
            AND   ah.action_code = ''SUBMIT''
            AND   ah.object_sub_type_code = h.type_lookup_code)
    AND   h.org_id = ##$$ORGID$$##
    AND   h.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   nvl(h.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(h.change_requested_by,''NONE'') NOT IN (''REQUESTER'',''SUPPLIER'')
    AND   (nvl(h.ENCUMBRANCE_REQUIRED_FLAG, ''N'') <> ''Y'' OR
           h.type_lookup_code <> ''BLANKET'')
    AND   NOT EXISTS (
            SELECT null
            FROM wf_item_activity_statuses ias,
                 wf_notifications n
            WHERE ias.notification_id is not null
            AND   ias.notification_id = n.group_id
            AND   n.status = ''OPEN''
            AND   ias.item_type = ''POAPPRV''
            AND   ias.item_key IN (
                    SELECT i.item_key FROM wf_items i
                    START WITH i.item_type = ''POAPPRV''
                    AND        i.item_key = h.wf_item_key
                    CONNECT BY PRIOR i.item_type = i.parent_item_type
                    AND        PRIOR i.item_key = i.parent_item_key
                    AND     nvl(i.end_date,sysdate+1) >= sysdate))
    AND   NOT EXISTS (
            SELECT 1
            FROM po_lines_all l,
                 po_line_locations_all s,
                 po_distributions_all d
            WHERE  s.line_location_id = d.line_location_id
            AND   l.po_line_id = s.po_line_id
            AND   d.po_header_id = h.po_header_id
            AND   l.matching_basis = ''QUANTITY''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(s.cancel_flag, ''N'') = ''N''
            AND   nvl(s.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   nvl(s.shipment_type,''BLANKET'') = ''STANDARD''
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round((s.price_override * d.quantity_ordered *
                    nvl(d.rate, 1) + nvl(d.nonrecoverable_tax, 0) *
                    nvl(d.rate, 1)), 2)
            UNION
            SELECT 1
            FROM po_lines_all l,
                 po_line_locations_all s,
                 po_distributions_all d
            WHERE  s.line_location_id = d.line_location_id
            AND   l.po_line_id = s.po_line_id
            AND   d.po_header_id = h.po_header_id
            AND   l.matching_basis = ''AMOUNT''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(s.cancel_flag, ''N'') = ''N''
            AND   nvl(s.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   nvl(s.shipment_type,''BLANKET'') = ''STANDARD''
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round((d.amount_ordered +
                    nvl(d.nonrecoverable_tax, 0)) *
                    nvl(d.rate, 1), 2))
    AND   NOT EXISTS (
            SELECT 1
            FROM po_lines_all l,
                 po_line_locations_all s,
                 po_distributions_all d
            WHERE  s.line_location_id = d.line_location_id
            AND   l.po_line_id = s.po_line_id
            AND   d.po_header_id = h.po_header_id
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   nvl(s.shipment_type,''BLANKET'') = ''PLANNED'')
    UNION
    SELECT ''RELEASE'',
           h.segment1,
           h.po_header_id,
           h.org_id,
           r.release_num,
           r.po_release_id,
           r.release_type,
           r.authorization_status,
           nvl(r.cancel_flag,''N'') canceled,
           nvl(r.closed_code,''OPEN'') closed_code,
           r.change_requested_by,
           r.revision_num,
           r.wf_item_type, r.wf_item_type "##$$FK1$$##",
           r.wf_item_key, r.wf_item_key "##$$FK2$$##",
           r.approved_date
    FROM po_headers_all h,
         po_releases_all r
    WHERE to_date(''##$$FDATE$$##'') <= (
            SELECT max(ah.action_date) FROM po_action_history ah
            WHERE ah.object_id = r.po_release_id
            AND   ah.object_type_code = ''RELEASE''
            AND   ah.action_code = ''SUBMIT''
            AND   ah.object_sub_type_code = r.release_type)
    AND   h.org_id = ##$$ORGID$$##
    AND   r.po_header_id = h.po_header_id
    AND   r.org_id = h.org_id
    AND   r.authorization_status IN (''IN PROCESS'',''PRE-APPROVED'')
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   nvl(r.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(r.change_requested_by,''NONE'') NOT IN (''REQUESTER'',''SUPPLIER'')
    AND   NOT EXISTS (
            SELECT null
            FROM wf_item_activity_statuses ias,
                 wf_notifications          n
            WHERE ias.notification_id is not null
            AND   ias.notification_id = n.group_id
            AND   n.status = ''OPEN''
            AND   ias.item_type = ''POAPPRV''
            AND   ias.item_key = r.wf_item_key)
    UNION
    SELECT ''REQUISITION'',
           h.segment1,
           h.requisition_header_id,
           h.org_id,
           null,
           null,
           h.type_lookup_code,
           h.authorization_status,
           nvl(h.cancel_flag,''N'') canceled,
           nvl(h.closed_code,''OPEN'') closed_code,
           null,
           null,
           h.wf_item_type, h.wf_item_type "##$$FK1$$##",
           h.wf_item_key, h.wf_item_key "##$$FK2$$##",
           h.approved_date
    FROM po_requisition_headers_all h
    WHERE to_date(''##$$FDATE$$##'') <= (
            SELECT max(ah.action_date) FROM po_action_history ah
            WHERE ah.object_id = h.requisition_header_id
            AND   ah.object_type_code = ''REQUISITION''
            AND   ah.action_code = ''SUBMIT''
            AND   ah.object_sub_type_code = h.type_lookup_code)
    AND   h.org_id = ##$$ORGID$$##
    AND   h.authorization_status IN (''IN PROCESS'', ''PRE-APPROVED'')
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   nvl(h.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(transferred_to_oe_flag,''N'') <> ''Y''
    AND   NOT EXISTS (
            SELECT 1 FROM po_requisition_lines_all rl
            WHERE  rl.requisition_header_id = h.requisition_header_id
            AND    rl.line_location_id is not null)
    AND   NOT EXISTS (
            SELECT null
            FROM wf_item_activity_statuses ias,
                 wf_notifications n
            WHERE ias.notification_id is not null
            AND   ias.notification_id = n.group_id
            AND   n.status = ''OPEN''
            AND   ias.item_type = ''REQAPPRV''
            AND   ias.item_key IN (
                    SELECT i.item_key FROM wf_items i
                    START WITH i.item_type = ''REQAPPRV''
                    AND        i.item_key = h.wf_item_key
                    CONNECT BY PRIOR i.item_type = i.parent_item_type
                    AND        PRIOR i.item_key = i.parent_item_key
                    AND        nvl(i.end_date,sysdate+1) >= sysdate))
    AND   NOT EXISTS (
            SELECT 1
            FROM po_requisition_lines_all l,
                 po_req_distributions_all d
            WHERE l.requisition_header_id = h.requisition_header_id
            AND   d.requisition_line_id = l.requisition_line_id
            AND   l.matching_basis = ''QUANTITY''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(l.cancel_flag, ''N'') = ''N''
            AND   nvl(l.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round(l.unit_price * d.req_line_quantity +
                    nvl(d.nonrecoverable_tax, 0), 2)
            UNION
            SELECT 1
            FROM po_requisition_lines_all l,
                 po_req_distributions_all d
            WHERE l.requisition_header_id = h.requisition_header_id
            AND   d.requisition_line_id = l.requisition_line_id
            AND   l.matching_basis = ''AMOUNT''
            AND   nvl(d.encumbered_flag, ''N'') = ''Y''
            AND   nvl(l.cancel_flag, ''N'') = ''N''
            AND   nvl(l.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
            AND   nvl(d.prevent_encumbrance_flag, ''N'') = ''N''
            AND   d.budget_account_id IS NOT NULL
            AND   round(nvl(d.encumbered_amount, 0), 2) <>
                    round(d.req_line_amount +
                    nvl(d.nonrecoverable_tax, 0), 2))
    ORDER BY 1,2',
   'Recent Documents - Candidates for Reset',
   'RS',
   'Recent documents exist which are candidates for reset.  The documents
    listed are all IN PROCESS or PRE-APPROVED approval status
    and do not have an open workflow notification.',
   '<ul><li>Review the results in the Workflow Activity section
         for the documents.</li>
      <li>If multiple documents are stuck with errors in the same
         workflow activity then try the Mass Retry in [458216.1].</li>
      <li>For all other document see [390023.1] for details on
         how to reset these documents if needed.</li>
      <li>To obtain a summary count for all such documents in your 
         system by document type, refer to [1584264.1]</li></ul>',
   null,
   'FAILURE',
   'W',
   'RS',
   'Y',
   l_info,
   VARCHAR_TBL('Note390023.1_case_GEN4_CHILD1',
     'Note390023.1_case_GEN4_CHILD2'));

    -------------------------------------------
    -- Note 390023.1 General Case 4 - WF Child 1
    -------------------------------------------
    l_info.delete;
    add_signature(
     'Note390023.1_case_GEN4_CHILD1',
     'SELECT DISTINCT
             ac.name Activity,
             ias.activity_result_code Result,
             ias.error_name ERROR_NAME,
             ias.error_message ERROR_MESSAGE,
             ias.error_stack ERROR_STACK
      FROM wf_item_activity_statuses ias,
           wf_process_activities pa,
           wf_activities ac,
           wf_activities ap,
           wf_items i
      WHERE ias.item_type = ''##$$FK1$$##''
      AND   ias.item_key  = ''##$$FK2$$##''
      AND   ias.activity_status     = ''ERROR''
      AND   ias.process_activity    = pa.instance_id
      AND   pa.activity_name        = ac.name
      AND   pa.activity_item_type   = ac.item_type
      AND   i.item_type             = ias.item_type
      AND   i.item_key              = ias.item_key
      AND   i.begin_date            >= ac.begin_date
      AND   i.begin_date            < nvl(ac.end_date, i.begin_date+1)
      AND   (ias.error_name is not null OR
             ias.error_message is not null OR
             ias.error_stack is not null)
      ORDER BY 1,2',
     'WF Activity Errors for This Document',
     'NRS',
     'No errored WF activities found for the document',
     null,
     null,
     'SUCCESS',
     'I',
     'RS');

    -------------------------------------------
    -- Note 390023.1 General Case 4 - WF Child 2
    -------------------------------------------
    l_info.delete;
    add_signature(
     'Note390023.1_case_GEN4_CHILD2',
     'SELECT DISTINCT
             iav.name Attribute,
             pa.process_name,
             pa.activity_name,
             ias.activity_result_code Result,
             nvl(iav.text_value,
               to_char(iav.number_value)) error_msg
      FROM wf_item_activity_statuses ias,
           wf_process_activities pa,
           wf_item_attribute_values iav
      WHERE ias.item_type = ''##$$FK1$$##''
      AND   ias.item_key  = ''##$$FK2$$##''
      AND   iav.item_type = ias.item_type
      AND   iav.item_key = ias.item_key
      AND   ias.activity_status  = ''ERROR''
      AND   iav.name in (''SYSADMIN_ERROR_MSG'',''PLSQL_ERROR_MSG'')
      AND   (iav.text_value is not null OR
             iav.number_value is not null)
      AND   ias.process_activity = pa.instance_id
      ORDER BY 1,2',
     'WF Error Attribute Values for This Document',

     'NRS',
     null,
     null,
     null,
     'SUCCESS',
     'I',
     'RS');

/*#################################################
  #   A p p r o v a l  H i e r a r c h y  S i g s #
  #################################################*/


  l_info.delete;
  add_signature(
   'APP_POS_HIERARCHY_MAIN',
   'SELECT /*+ ordered use_nl(eh, p, a, pos, poss) */
           p.full_name,
           eh.superior_id person_id,
           eh.superior_id "##$$FK1$$##",
           eh.superior_level,
           pos.position_id,
           pos.position_id "##$$FK2$$##",
           pos.name position_name,
           poss.name hierarchy_name,
           poss.position_structure_id hierarchy_id
    FROM --hr_employees_current_v ec,
         --po_employees_current_x ec,
         po_employee_hierarchies_all eh,
         per_all_people_f p,
         per_all_assignments_f a,
         per_all_positions pos,
         per_position_structures poss
    WHERE eh.position_structure_id = ##$$APPATH$$##
    AND   eh.employee_id = ##$$PREPID$$##
    AND   eh.business_group_id IN (
            SELECT fsp.business_group_id
            FROM financials_system_params_all fsp
            WHERE fsp.org_id = ##$$ORGID$$##)
    AND   p.person_id = eh.superior_id
    AND   (eh.superior_level > 0 OR
           eh.superior_id = eh.employee_id)
    AND   a.person_id = p.person_id
    AND   a.primary_flag = ''Y''
    AND   trunc(sysdate) BETWEEN p.effective_start_date AND
            p.effective_end_date
    AND   trunc(sysdate) BETWEEN a.effective_start_date AND
            a.effective_end_date
    AND   (nvl(p.current_employee_flag, ''N'') = ''Y'' OR
           nvl(p.current_npw_flag, ''N'') = ''Y'')
    AND   a.assignment_type in (''E'',
            decode(nvl(fnd_profile.value(''HR_TREAT_CWK_AS_EMP''), ''N''),
              ''Y'', ''C'',
              ''E''))
    AND   pos.position_id (+) = a.position_id
    AND   poss.position_structure_id (+) = eh.position_structure_id
   UNION
   SELECT /*+ ordered use_nl(poeh, cwk, a, ps, pos, poss) */
          cwk.full_name,
          poeh.superior_id person_id,
          poeh.superior_id "##$$FK1$$##",
          poeh.superior_level,
          pos.position_id,
          pos.position_id "##$$FK2$$##",
          pos.name position_name,
          poss.name hierarchy_name,
          poss.position_structure_id hierarchy_id
   FROM po_employee_hierarchies_all poeh,
        per_all_people_f cwk,
        per_all_assignments_f a,
        per_periods_of_service ps,
        per_all_positions pos,
        per_position_structures poss
   WHERE poeh.position_structure_id = ##$$APPATH$$##
   AND   poeh.employee_id = ##$$PREPID$$##
   AND   poeh.business_group_id IN (
           SELECT fsp.business_group_id
           FROM financials_system_params_all fsp
           WHERE fsp.org_id = ##$$ORGID$$##)
   AND   cwk.person_id = poeh.superior_id
   AND   (poeh.superior_level > 0 OR
          poeh.superior_id = poeh.employee_id)
   AND   nvl(fnd_profile.value(''HR_TREAT_CWK_AS_EMP''),''N'') = ''Y''
   AND   a.person_id = cwk.person_id
   AND   a.person_id = ps.person_id
   AND   a.assignment_type=''E''
   AND   cwk.employee_number is not null
   AND   a.period_of_service_id = ps.period_of_service_id
   AND   a.primary_flag = ''Y''
   AND   trunc(sysdate) BETWEEN cwk.effective_start_date AND
           cwk.effective_end_date
   AND   trunc(sysdate) BETWEEN a.effective_start_date AND
           a.effective_end_date
   AND    (ps.actual_termination_date >= trunc(sysdate) OR
           ps.actual_termination_date is null)
   AND   poss.position_structure_id (+) = poeh.position_structure_id
   AND   pos.position_id (+) = a.position_id
   UNION
   SELECT /*+ ordered use_nl(poeh, cwk, a, pp, pos, poss) */
          cwk.full_name,
          poeh.superior_id ,
          poeh.superior_id "##$$FK1$$##",
          poeh.superior_level,
          pos.position_id,
          pos.position_id "##$$FK2$$##",
          pos.name position_name,
          poss.name hierarchy_name,
          poss.position_structure_id hierarchy_id
   FROM per_all_people_f cwk,
        po_employee_hierarchies poeh,
        per_all_assignments_f a,
        per_periods_of_placement pp,
        per_all_positions pos,
        per_position_structures poss
   WHERE poeh.position_structure_id = ##$$APPATH$$##
   AND   poeh.employee_id = ##$$PREPID$$##
   AND   cwk.person_id = poeh.superior_id
   AND   (poeh.superior_level > 0 OR
          poeh.superior_id = poeh.employee_id)
   AND   nvl(fnd_profile.value(''HR_TREAT_CWK_AS_EMP''),''N'') = ''Y''
   AND   a.person_id = cwk.person_id
   AND   a.person_id = pp.person_id
   AND   a.assignment_type = ''C''
   AND   cwk.npw_number is not null
   AND   a.period_of_placement_date_start = pp.date_start
   AND   a.primary_flag = ''Y''
   AND   trunc(sysdate) BETWEEN cwk.effective_start_date AND
           cwk.effective_end_date
   AND   trunc(sysdate) BETWEEN a.effective_start_date AND
           a.effective_end_date
   AND   (pp.actual_termination_date >= trunc(sysdate) OR
          pp.actual_termination_date is null)
   AND   poss.position_structure_id (+) = poeh.position_structure_id
   AND   pos.position_id (+) = a.position_id
   ORDER BY 4, 1',
   'Approving Employee',
   'NRS',
   'No approvers found for approval hierarchy ID: '||
    g_sql_tokens('##$$APPATH$$##')||' or no default approval hierarchy found',
   'If the approval hierarchy ID is NULL make sure the document type has
    a default approval path:
    <ol><li>Go to the document types form. (Navigation: 
        PO Responsibility > Setup > Purchasing > Document Types)</li>
     <li>Query the specific document type i.e. Purchase Order</li>
     <li>Associate a default hierarchy.</li></ol>',
   null,
   'ALWAYS',
    'W',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('APP_HIER_CHECK2', 'APP_HIER_CHECK3',
      'APP_HIER_CHECK4', 'APP_HIER_CHECK5', 'APP_HIER_CHECK6'
      ));

  l_info.delete;
  add_signature(
   'APP_SUP_HIERARCHY_MAIN',
   'SELECT p1.full_name employee_name,
           h.employee_id,
           h.employee_id "##$$FK1$$##",
           p2.full_name supervisor_name,
           h.supervisor_id,
           j.name job_name,
           h.job_id,
           h.job_id "##$$FK2$$##",
           h.hier_level lvl,
           h.loop
    FROM per_all_people_f p1,
         per_all_people_f p2,
         per_jobs j,
         (
           SELECT a.person_id employee_id,
                  a.assignment_id,
                  a.effective_start_date,
                  a.effective_end_date,
                  a.supervisor_id,
                  a.job_id,
                  level hier_level,
                  decode(connect_by_iscycle,
                    0, ''No'',
                    ''Yes'') loop
           FROM per_assignments_f a
           WHERE EXISTS (
                   SELECT ''1''
                   FROM per_people_f p, per_assignments_f a1
                   WHERE trunc(sysdate) BETWEEN p.effective_start_date AND
                           p.effective_end_date
                   AND   p.person_id = a.person_id
                   AND   a1.person_id = p.person_id
                   AND   trunc(sysdate) BETWEEN a1.effective_start_date AND
                           a1.effective_end_date
                   AND   a1.primary_flag = ''Y''
                   AND   a1.ASSIGNMENT_TYPE IN (''E'',''C'')
                   AND   EXISTS (
                         SELECT ''1''
                         FROM per_person_types pt,
                              per_person_type_usages_f ptu
                         WHERE ptu.person_id = p.person_id
                         AND   pt.system_person_type IN (''EMP'',''EMP_APL'',''CWK'')
                         AND   pt.person_type_id = ptu.person_type_id))
           START WITH a.person_id = ##$$PREPID$$##
                AND   trunc(sysdate) BETWEEN a.effective_start_date AND
                        a.effective_end_date
                AND   a.primary_flag = ''Y''
                AND   a.ASSIGNMENT_TYPE IN (''E'',''C'')
           CONNECT BY NOCYCLE PRIOR a.supervisor_id = a.person_id
                AND   trunc(sysdate) BETWEEN a.effective_start_date AND
                        a.effective_end_date
                AND   a.primary_flag = ''Y''
                AND   a.ASSIGNMENT_TYPE IN (''E'',''C'')
         ) h
    WHERE p1.person_id = h.employee_id
    AND   trunc(sysdate) BETWEEN p1.effective_start_date AND
                         p1.effective_end_date
    AND   p2.person_id (+) = h.supervisor_id
    AND   trunc(sysdate) BETWEEN p2.effective_start_date (+) AND
                         p2.effective_end_date (+)
    AND   j.job_id = h.job_id
    ORDER BY h.hier_level',
    'Approving Employee',
    '[LOOP]=[Yes]',
    'There is a loop in the employee/supervisor hierarchy',
    'Review the list of approvers shown above and modify the approval hierarchy so there is no loop in the employee/supervisor hierarchy.',
    NULL,
    'ALWAYS',
    'W',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('APP_HIER_CHECK1', 'APP_HIER_CHECK3',
      'APP_HIER_CHECK4', 'APP_HIER_CHECK5', 'APP_HIER_CHECK6'
      ),
    p_include_in_dx_summary => 'Y');

  l_info.delete;
  add_signature(
   'APP_HIER_CHECK1',
   'SELECT pc.org_id,
           cf.control_function_name,
           cg.control_group_name,
           cr.rule_type_code,
           cr.object_code ,
           to_char(cr.amount_limit) amount_limit,
           (cr.segment1_low||''.''||cr.segment2_low||''.''||
             cr.segment3_low||''.''||cr.segment4_low||''.''||
             cr.segment5_low||''.''||cr.segment6_low||''.''||
             cr.segment7_low||''.''||cr.segment8_low||''.''||
             cr.segment9_low||''.''||cr.segment10_low||''.''||
             cr.segment11_low||''.''||cr.segment12_low) Account_Range_Low,
           (cr.segment1_high||''.''||cr.segment2_high||''.''||
             cr.segment3_high||''.''||cr.segment4_high||''.''||
             cr.segment5_high||''.''||cr.segment6_high||''.''||
             cr.segment7_high||''.''||cr.segment8_high||''.''||
             cr.segment9_high||''.''||cr.segment10_high||''.''||
             cr.segment11_high||''.''||cr.segment12_high) Account_Range_High
    FROM po_position_controls_all pc,
         po_control_groups_all cg,
         po_control_functions cf,
         po_control_rules cr
    WHERE pc.control_group_id = cg.control_group_id
    AND   cr.control_group_id = pc.control_group_id
    AND   pc.control_function_id = cf.control_function_id
    AND   pc.org_id = ##$$ORGID$$##
    AND   pc.job_id = ##$$FK2$$##
    AND   cf.document_type_code = ''##$$TRXTP$$##''
    AND   cf.document_subtype = ''##$$SUBTP$$##''
    AND   trunc(sysdate) BETWEEN pc.start_date AND nvl(pc.end_date,sysdate+1)
    AND   cf.enabled_flag = ''Y''
    AND   cg.enabled_flag = ''Y''
    ORDER BY pc.control_function_id, pc.control_group_id,
             cr.object_code, cr.rule_type_code desc',
    'Job Approval Assignments',
    'NRS',
    'No approval assignments found for this document type and job.',
    'Assign an approval group to this document type and job if needed.
     (Navigation: PO Responsibility > Setup > Approvals > Approval Assignments.)',
    null,
    'ALWAYS',
    'W',
    'RS',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'APP_HIER_CHECK2',
   'SELECT pc.org_id,
           cf.control_function_name,
           cg.control_group_name,
           cr.rule_type_code,
           cr.object_code,
           to_char(cr.amount_limit) amount_limit,
           (cr.segment1_low||''.''||cr.segment2_low||''.''||
            cr.segment3_low||''.''||cr.segment4_low||''.''||
            cr.segment5_low||''.''||cr.segment6_low||''.''||
            cr.segment7_low||''.''||cr.segment8_low||''.''||
            cr.segment9_low||''.''||cr.segment10_low||''.''||
            cr.segment11_low||''.''||cr.segment12_low) account_range_low,
           (cr.segment1_high||''.''||cr.segment2_high||''.''||
           cr.segment3_high||''.''||cr.segment4_high||''.''||
           cr.segment5_high||''.''||cr.segment6_high||''.''||
           cr.segment7_high||''.''||cr.segment8_high||''.''||
           cr.segment9_high||''.''||cr.segment10_high||''.''||
           cr.segment11_high||''.''||cr.segment12_high) account_range_high
    FROM po_position_controls_all pc,
         po_control_groups_all cg,
         po_control_functions cf,
         po_control_rules cr
    WHERE pc.control_group_id = cg.control_group_id
    AND   pc.control_function_id = cf.control_function_id
    AND   pc.org_id = ##$$ORGID$$##
    AND   cf.document_type_code = ''##$$TRXTP$$##''
    AND   cf.document_subtype = ''##$$SUBTP$$##''
    AND   pc.position_id = TO_NUMBER(DECODE(''##$$FK2$$##'', '''', -3, NULL, -3, ''##$$FK2$$##''))
    AND   trunc(sysdate) BETWEEN pc.start_date AND nvl(pc.end_date,sysdate+1)
    AND   cr.control_group_id = pc.control_group_id
    AND   cf.enabled_flag = ''Y''
    AND   cg.enabled_flag = ''Y''
    ORDER BY pc.control_function_id, pc.control_group_id,
             cr.object_code, cr.rule_type_code DESC',
    'Position Approval Assignments',
    'NRS',
    'No approval assignments found for this document type and position.',
    'Assign an approval group to this document type and position if needed.
     (Navigation: PO Responsibility > Setup > Approvals > Approval Assignments.)',
    null,
    'ALWAYS',
    'W',
    'RS',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'APP_HIER_CHECK3',
   'SELECT po_apprvl_analyzer_pkg.get_result result_code,
           po_apprvl_analyzer_pkg.get_fail_msg failure_message,
           po_apprvl_analyzer_pkg.get_exc_msg exception_message
    FROM dual',
    'Does Employee Have Authority to Approve',
    '[result_code]<>[S:NULL]',
    'This employee is not authorized to approve this document',
    'Review the failure and exception messages above to determine the reason',
    'This employee does have authority to approve the document',
    'ALWAYS',
    'I',
    'N',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'APP_HIER_CHECK4',
   'SELECT rownum num,
           fu.employee_id,
           fu.user_id,
           fu.user_name,
           fu.email_address,
           fu.start_date,
           fu.end_date
    FROM fnd_user fu
    WHERE employee_id = ##$$FK1$$##
    AND   trunc(sysdate) BETWEEN fu.start_date AND
            nvl(fu.end_date, sysdate+1)',
    'Application User',
    '[num]>[1]',
    'This employee is assigned to multiple applications users',
    'Please ensure the employee is associated to only one application user: 
     <ol><li>Go to the Define Users form. (Navigation:
             System Administrator Responsibility > Security > Users > Define</li>
        <li>Use the employee name to find the user records</li>
        <li>Reassign or disable the users to ensure that only one active user
            is associated to the employee</li>
        <li>Save changes</li></ol>',
    null,
    'FAILURE',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'APP_HIER_CHECK5',
   'SELECT rownum num,
           fu.employee_id,
           fu.user_id,
           fu.user_name,
           fu.email_address,
           fu.start_date,
           fu.end_date
    FROM fnd_user fu
    WHERE employee_id = ##$$FK1$$##
    AND   trunc(sysdate) BETWEEN fu.start_date AND
            nvl(fu.end_date, sysdate+1)',
    'Application User',
    'NRS',
    'This employee is not assigned to any active applications user.',
    'Please make sure employee is assigned to a valid applications
     user and verify the start and end dates include the current date: 
     <ol><li>Go to the Define Users form. (Navigation:
             System Administrator Responsibility > Security > Users > Define</li>
        <li>Use the employee name to find the user record</li>
        <li>If no user is found, one should be created for the employee
        <li>If a user is found, ensure that it is not end dated
           (i.e., the effective end date is null or
            later than current date). The user will be automatically
            end-dated when password expires depending on the password
            expiration settings defined in the Define Users form.</li>
        <li>Save all changes</li></ol>',
    null,
    'FAILURE',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'APP_HIER_CHECK6',
   'SELECT name,
           display_name,
           notification_preference,
           email_address,
           status,
           start_date,
           expiration_date
    FROM wf_users
    WHERE orig_system_id = ##$$FK1$$##
    AND orig_system = ''PER''
    AND status = ''ACTIVE''',
    'Workflow User',
    'NRS',
    'This employee does not exist in the workflow tables (WF_USERS)',
    'Follow these steps to create the user: 
        <ol>
        <li>Go to the Define Users form. (Navigation:
          System Administrator Responsibility > Security > Users > Define</li>
        <li>Query the applications user for this employee</li>
        <li>Remove values from person name and email address and save changes</li>
        <li>Re-Query the user</li>
        <li>Re-add the data in the person region and save the changes</li></ol>',
    null,
    'FAILURE',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');


/*####################################
  # P a c k a g e   V e r s i o n s  #
  ####################################*/
  add_signature(
   'PACKAGE_VERSIONS',
   'SELECT name,
           type,
           regexp_replace(
             regexp_replace(text, ''.*\$Header: *'', '''', 1, 1),
               '' *[0-9]{4}\/.*$'','''',1,1) "File Version"
    FROM dba_source
    WHERE ((text like ''%$Header: POXWPA%'' and name like ''PO_%'') OR
           (text like ''%$Header: %'' and name like ''POR_AME%'') OR
           (text like ''%$Header: %'' and name like ''AME_API%''))
    ORDER BY name, type',
    'PO and AME Package Versions',
    'NRS',
    'No package file versions found.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');
    
    
/*####################################
  # WFT file versions                #
  ####################################*/
  add_signature(
   'PO_WF_FILE_VERSIONS',
   'select af.filename, av.version
     from ad_files af,
          ad_file_versions av
     where af.file_id= av.file_id
       and lower(af.filename) in 
           (''poxwfpoa.wft'', ''poxwfrqa.wft'', ''poxwfatc.wft'', ''poxwfstd.wft'', ''poswfpag.wft'', ''poxwfrag.wft'', ''poxwfarm.wft'', ''poxwfrcv.wft'')
       and af.subdir like ''%US%''
       and av.version=(select max (version) from ad_file_versions afv where afv.file_id=af.file_id)',
    'Workflow File (WFT) Versions',
    'NRS',
    'No file versions found.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');    

    
/*####################################
  #   W F S T A T  S i g s           #
  ####################################*/

  add_signature(
   'WFSTAT_ITEM',
   'SELECT ITEM_TYPE,
        ITEM_KEY,
        PARENT_ITEM_TYPE,
        PARENT_ITEM_KEY,
        PARENT_CONTEXT,
        to_char(BEGIN_DATE,''DD-MON-RR HH24:MI:SS'') BEGIN_DATE,
        to_char(END_DATE,''DD-MON-RR HH24:MI:SS'') END_DATE,
  ROOT_ACTIVITY,
        ROOT_ACTIVITY_VERSION,
        OWNER_ROLE
      FROM wf_items
     WHERE item_type = ''##$$ITMTYPE$$##''
       AND item_key = ''##$$ITMKEY$$##''',
    'WFStat: Workflow Item',
    'NRS',
    'No WF Item Type found for the combination of Item Type / Item Key',
    'This likely due to the WF_ITEMS table being purged',
    NULL,
    'ALWAYS',
    'W',
    'RS');

  add_signature(
   'WFSTAT_CHILD_PROCESSES',
   'SELECT parent_item_type,
           parent_item_key,
           parent_context,
           item_type,
           item_key,
           to_char(begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
           to_char(end_date,''DD-MON-RR HH24:MI:SS'') end_date,
           root_activity,
           root_activity_version,
           owner_role
    FROM wf_items
    WHERE parent_item_type = ''##$$ITMTYPE$$##''
    AND   parent_item_key = ''##$$ITMKEY$$##''',
    'WFStat: Child Processes',
    'RS',
    'WF Child Processes found for the combination of Item Type / Item Key',
    NULL,
    'No WF Child Processes found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');

  add_signature(
   'WFSTAT_ACTIVITY_STATUSES',
   'SELECT to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
           to_char(ias.end_date,''DD-MON-RR HH24:MI:SS'') end_date,
           ap.name||'' / ''||pa.instance_label "Process / Activity",
           ap.display_name "Process Name",
           ac.display_name "Activity Name",
           ias.activity_status Status,
           ias.activity_result_code Result,
           ias.assigned_user assigned_user,
           ias.notification_id NID,
           ntf.status "Status",
           ias.action,
           ias.performed_by
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities_vl ap,
         wf_items i,
  wf_notifications ntf
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ntf.notification_id(+) = ias.notification_id
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Activity Statuses',
    'RS',
    'WF Activity Statuses found for the combination of Item Type / Item Key',
    NULL,
    'No WF Activity Statuses found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS',
    'N');

  add_signature(
   'WFSTAT_ACTIVITY_STATUSES_HISTORY',
   'SELECT to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
           ap.name||'' / ''||pa.instance_label "Process / Activity",
           ap.display_name "Process Name",
           ac.display_name "Activity Name",
           ias.activity_status Status,
           ias.activity_result_code Result,
           ias.assigned_user assigned_user,
           ias.notification_id NID,
           ntf.status "Status",
           ias.action,
           ias.performed_by
    FROM wf_item_activity_statuses_h ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities_vl ap,
         wf_items i,
         wf_notifications ntf
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ntf.notification_id(+) = ias.notification_id
order by ias.begin_date, ias.execution_time',
    'WFStat: Activity Statuses History',
    'RS',
    'WF Activity Status History found for the combination of Item Type / Item Key',
    NULL,
    'No WF Activity Status History found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');

  add_signature(
   'WFSTAT_NOTIFICATIONS',
   'SELECT wn.notification_id nid,
           wn.notification_id "##$$FK1$$##",
           wn.context,
           wn.group_id,
           wn.status,
           wn.mail_status,
           wn.message_type,
           wn.message_name,
           wn.access_key,
           wn.priority,
           wn.begin_date,
           wn.end_date,
           wn.due_date,
           wn.callback,
           wn.recipient_role,
           wn.responder,
           wn.original_recipient,
           wn.from_user,
           wn.to_user,
           wn.subject
    FROM wf_notifications wn,
         wf_item_activity_statuses wias
    WHERE wn.group_id = wias.notification_id
    AND   wias.item_type = ''##$$ITMTYPE$$##''
    AND   wias.item_key  = ''##$$ITMKEY$$##''',
    'WFStat: Notifications',
    'RS',
    'Notifications found for the combination of Item Type / Item Key',
    NULL,
    'No Notifications found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('WFSTAT_NOTIFICATION_ACTIVITY', 'WFSTAT_NOTIFICATION_MESSAGES'));
    
    l_info.delete;
    
  /*******************************************/  
  /* WF NOTIFICATION ACTIVITY CHILD SIG      */
  /*******************************************/  
    
  add_signature(
   'WFSTAT_NOTIFICATION_ACTIVITY',
   'SELECT DISTINCT
    ACT.NAME             NOTIFICATION
  , ACT.RESULT_TYPE      RESULT
  , ACT.MESSAGE          MESSAGE
  , ACT.FUNCTION         PLSQL_FUNCTION
  , decode((select STATUS from all_objects
     where OBJECT_NAME = substr(ACT.FUNCTION,1,instr(ACT.FUNCTION,''.'')-1)
     and OWNER = ''APPS''
     and OBJECT_TYPE = ''PACKAGE BODY''),
    ''VALID'',   ''Y'',
    ''INVALID'', ''N'',
    ''X'') VAL
  , T.DISPLAY_NAME     DISPLAY_NAME 
from WF_ACTIVITIES               ACT
   , WF_ACTIVITIES_TL            T
   , WF_PROCESS_ACTIVITIES       PRO
   , WF_ITEM_ACTIVITY_STATUSES   STA
   , WF_ITEMS                    ITM
where  STA.NOTIFICATION_ID  = ##$$FK1$$##
   and ACT.ITEM_TYPE  = T.ITEM_TYPE
   and ACT.NAME      = T.NAME
   and ACT.VERSION   = T.VERSION
   and T.LANGUAGE  = userenv(''LANG'')
   and STA.PROCESS_ACTIVITY = PRO.INSTANCE_ID
   and ITM.ITEM_TYPE        = STA.ITEM_TYPE
   and ITM.ITEM_KEY         = STA.ITEM_KEY
   and ITM.BEGIN_DATE      >= ACT.BEGIN_DATE
   and ITM.BEGIN_DATE       < nvl(ACT.END_DATE,ITM.BEGIN_DATE+1)
   and ACT.NAME             = PRO.ACTIVITY_NAME
   and ACT.ITEM_TYPE        = PRO.ACTIVITY_ITEM_TYPE
   ',
    'WFStat: Notification Activities',
    'RS',
    'Notification activities found for the combination of Item Type / Item Key',
    NULL,
    'No Notification activities found for the combination of Item Type / Item Key',
    'FAILURE',
    'I',
    'RS');
   
   
  add_signature(
      'WFSTAT_NOTIFICATION_MESSAGES',
      'SELECT 
        B.NAME                        MESSAGE
      , T.DISPLAY_NAME                DISPLAY_NAME
      , B.DEFAULT_PRIORITY            PRTY
      , T.SUBJECT   SUBJECT
      , ''Text Body = '' || wf_core.newline  
                       ||T.BODY       TEXT_BODY
      , wf_core.newline ||''HTML Body = '' || wf_core.newline 
                       ||T.HTML_BODY  HTML_BODY 
    FROM WF_MESSAGES     B
      , WF_MESSAGES_TL   T 
      , WF_NOTIFICATIONS N
    WHERE B.TYPE             = T.TYPE
       AND B.NAME            = T.NAME
       AND T.LANGUAGE        = USERENV(''LANG'')
       AND B.TYPE            = N.MESSAGE_TYPE
       AND B.NAME            = N.MESSAGE_NAME
       AND N.NOTIFICATION_ID = ##$$FK1$$##
      ',
    'WFStat: Notification Messages',
    'RS',
    'Notification messages found for the combination of Item Type / Item Key',
    NULL,
    'No Notification messages found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');  

  add_signature(
   'WFSTAT_ERRORED_ACTIVITIES',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Errored Activities',
    'RS',
    'Errored Activities found for the combination of Item Type / Item Key',
    NULL,
    'No Errored Activities found for the combination of Item Type / Item Key',
    'ALWAYS',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');

    
  add_signature(
   'WFSTAT_ERROR_ORA_04061',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''%ORA-04061%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error ORA-04061',
    'RS',
    'The approval workflow process has errored with ORA-04061:
     existing state of &lt;object&gt; has been invalidated.',
    '<ul>
     <li>Follow the steps below from [303260.1] to resolve the error:
     <ol><li> Shut down the notification mailer</li>
       <li>Flush the shared pool using syntax below (as APPS user,
           which is safe to do):<br/><blockquote>
           SQL> alter system flush shared_pool;</blockquote></li>
       <li>Restart the notification mailer<br/><br/></li></ol></li>
     <li>If the above steps do not resolve the issue then also
         perform the steps below:
      <ol><li> Bring down the concurrent managers, forms server,
         and web server on the middle tier. It is recommended
         that $COMMON_TOP/admin/scripts/SID/adstpall.sh apps/apps
         or equivalent be used.</li>
       <li>Recompile the APPS schema using adadmin. Take note of
           invalid objects before (if any) - and then after -
           to ensure no new invalid objects are created.</li>
       <li>Bring the instance services back up - and retest
          the issue. Ensure the notification mailer is bounced
          when restarting the instance</li></ol></li></ul>',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');
    
    
  add_signature(
   'WFSTAT_ERROR_ORA_06512',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''%ORA-06512%''
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(PO_POAPPROVAL_INIT1.GET_PO_ATTRIBUTES, POAPPRV%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error ORA-06512',
    'RS',
    'The approval workflow process has errored with ORA-06512. This error happens when the quantity ordered or amount is zero in one of the Distributions (po_distributions_all).',
    'Follow the steps from [377334.1] to resolve the error. The note explains how to apply a data fix for the existing records and a code fix to prevent the issue from occurring in the future.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');

  add_signature(
   'WFSTAT_ERROR_20002',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ((ias.error_message like ''%20002%''
           AND (ias.error_stack like ''%ORA-04061: existing state of package "APPS.PO_EMAIL_GENERATE" has been invalidated%''
                OR ias.error_stack like ''%ORA-04061: existing state of package body "APPS.PO_REQAPPROVAL_INIT1" has been invalidated%''
                OR ias.error_stack like ''%existing state of has been invalidated ORA-04061: existing state of package body "APPS.PO_WF_REQ_NOTIFICATION"%''))
            OR ((ias.error_message like ''%ORA-06508%'')     
           AND (ias.error_stack like ''%Wf_Notification.Send%PO_PO_APPROVE_PDF%'' 
                OR ias.error_stack like ''%could not find program unit being called: "APPS.PO_REQAPPROVAL_FINDAPPRV1"%''))
           )       
    ',
    'WFStat: Error -20002',
    'RS',
    'The approval workflow process has errored because one database package is currently in an inconsistent state',
    'Follow the steps from [303260.1] to resolve this issue',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');
    
  add_signature(
   'WFSTAT_Note1268145.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
WHERE    ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(POR_AME_REQ_WF_PVT.Process_Beat_By_First%''
    ORDER BY ias.begin_date, ias.execution_time    
    ',
    'WFStat: Error ORA-06512',
    'RS',
    'The following error has occurred during Requisition approval: ORA-06512 in function call to POR_AME_REQ_WF_PVT.Process_Beat_By_First',
    'Follow the steps from [1268145.1] to resolve this issue',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    
    
  add_signature(
   'WFSTAT_Note1969021.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''%ORA-06512%''
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(POR_AME_REQ_WF_PVT.UPDATE_ACTION_HISTORY_APPROVE, REQAPPRV%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error ORA-06512',
    'RS',
    'The approval workflow process has errored with ORA-06512:
     Wf_Engine_Util.Function_Call(POR_AME_REQ_WF_PVT.UPDATE_ACTION_HISTORY_APPROVE, REQAPPRV...',
    'Follow the steps below from [1969021.1] to resolve the error.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    
    
  add_signature(
   'WFSTAT_Note1961339.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''%ORA-06512%''
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(PO_APPROVAL_LIST_WF1S.UPDATE_ACTION_HISTORY_FORWARD, REQAPPRV%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error ORA-06512',
    'RS',
    'The approval workflow process has errored with ORA-06512:
     Wf_Engine_Util.Function_Call(PO_APPROVAL_LIST_WF1S.UPDATE_ACTION_HISTORY_FORWARD, REQAPPRV...',
    'Follow the steps below from [1961339.1] to resolve the error.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    
        
    
  add_signature(
   'WFSTAT_Note1969203.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''%ORA-06512%''
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(PO_APPROVAL_LIST_WF1S.UPDATE_ACTION_HISTORY_APPROVE,REQAPPRV%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error ORA-06512',
    'RS',
    'The approval workflow process has errored with ORA-06512:
     Wf_Engine_Util.Function_Call(PO_APPROVAL_LIST_WF1S.UPDATE_ACTION_HISTORY_APPROVE,REQAPPRV...',
    'Follow the steps below from [1969203.1] to resolve the error.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    
    

  l_info.delete;  
    
  add_signature(
   'WFSTAT_Note1288874.1',
   'select pha.segment1 "PO Number"
       ,pha.org_id "Org"
       ,ias.item_type "Item Type"
       ,ias.item_key "Item Key"
       ,to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') "Begin Date"
       ,to_char(ias.end_date,''DD-MON-RR HH24:MI:SS'') "End Date"
       ,ap.name||''/''||pa.instance_label "Activity"
       ,ias.activity_status "Status"
       ,ias.activity_result_code "Result"
       ,wiav.NUMBER_VALUE "Request ID"
       from po_headers_all pha
       ,wf_item_activity_statuses ias
       ,wf_process_activities pa
       ,wf_activities ac
       ,wf_activities ap
       ,wf_items i
       ,wf_item_attribute_values wiav
     where ias.item_type = ''POAPPRV''
       and ias.item_key = ''##$$ITMKEY$$##''
       and ias.item_type = pha.wf_item_type
       and ias.item_key = pha.wf_item_key
       and pa.instance_label = ''WAITFORCONCURRENTPROGRAM''
       and ias.process_activity = pa.instance_id
       and pa.activity_name = ac.name
       and pa.activity_item_type = ac.item_type
       and pa.process_name = ap.name
       and pa.process_item_type = ap.item_type
       and pa.process_version = ap.version
       and i.item_type = ias.item_type
       and i.item_key = ias.item_key
       and i.begin_date >= ac.begin_date
       and i.begin_date < nvl(ac.end_date, i.begin_date+1)
       and ias.activity_result_code <> ''NORMAL'' 
       and wiav.item_key = ias.item_key
       and wiav.name = ''REQUEST_ID''
    ',
    'PO Approval Failing At "Wait for Concurrent Program"',
    'RS',
    'The PO Approval process has failed during "Wait for Concurrent Program" step.',
    'Follow the steps from [1288874.1] to resolve this issue',
    NULL,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('PRINTER_PROFILE', 'CONTRACT_TERMS', 'POXVCOMB_VERSION'),
    p_include_in_dx_summary => 'Y');    
    
    
  add_signature(
   'PRINTER_PROFILE',
   'SELECT t.user_profile_option_name "Profile Option",
        decode(a.level_id, 10001, ''Site'',
        10002, ''Application'',
        10003, ''Responsibility'',
        10004, ''User'') "Level",
        a.profile_option_value "Profile Value"
        FROM fnd_profile_option_values a,
        fnd_profile_options e,
        fnd_profile_options_tl t
        WHERE a.profile_option_id = e.profile_option_id
        AND e.profile_option_name = ''PRINTER''
        AND t.profile_option_name = e.profile_option_name
        AND t.LANGUAGE = ''US''
        AND a.level_id = 10001
    ',
    'No value for Profile Option "Printer"',
    'NRS',
    'Profile option "Printer" does not have a value set at Site level',
    '<ol>Please set a value for profile Printer at site level:
       <li> From the System Administrator responsibility
       <li> Navigate to Profile > System
       <li> Query profile option "Printer"
       <li> Set it at site level
       <li> Save the changes
       <li> Retest the functionality
    </ol>',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');               

  add_signature(
   'CONTRACT_TERMS',
   'select segment1, CONTERMS_EXIST_FLAG cef
      from po_headers_all
     where po_header_id = ##$$DOCID$$##
       and org_id = ##$$ORGID$$##
    ',
    'Contract Terms attached to PO',
    '[cef]=[Y]',
    'Contract Terms are attached to the PO. This might be a known issue.',
    'Please review [736810.1] and verify if the solution described is applicable.',
    NULL,
    'FAILURE',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');               
    
 
   add_signature(
   'POXVCOMB_VERSION',
   'select ds.text
    from dba_source ds, 
         dba_objects do
    where ds.name = ''PO_COMMUNICATION_PVT''
      and ds.line = 2
      and ds.name = do.object_name
      and ds.type = do.object_type
      and do.object_type = ''PACKAGE BODY''
      and po_apprvl_analyzer_pkg.chk_pkg_body_version(''PO_COMMUNICATION_PVT'', ''120.61.12010000.26'') < 0
    ',
    'Version of PO_COMMUNICATION_PVT',
    'RS',
    'Version of PPOXVCOMB.pls is lower than 120.61.12010000.26',
    'If the version is lower, please review [1252874.1] and follow the steps described in the note to fix this issue.',
    NULL,
    'FAILURE',
    'E',
    'RS',
    p_include_in_dx_summary => 'Y');           
    

    
  add_signature(
   'WFSTAT_Note1277855.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
WHERE    ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_stack like ''%Wf_Engine_Util.Function_Call(PO_REQAPPROVAL_ACTION.RESERVE_DOC%''
    ORDER BY ias.begin_date, ias.execution_time    
    ',
    'WFStat: PO_REQAPPROVAL_ACTION.RESERVE_DOC Error',
    'RS',
    'The following error has occurred during Requisition approval: Wf_Engine_Util.Function_Call(PO_REQAPPROVAL_ACTION.RESERVE_DOC, REQAPPRV, XXXXXX, XXXXX, RUN)',
    'Follow the steps from [1277855.1] to resolve this issue',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    



  add_signature(
   'WFSTAT_Note1995413.1',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = ''##$$ITMTYPE$$##''
    AND   ias.item_key = ''##$$ITMKEY$$##''
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.item_type = ''##$$ITMTYPE$$##''
    AND   i.item_key = ias.item_key
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ias.error_message like ''Activity%PORPOCHA%has no performer%''
    AND   ias.error_stack like ''%Wf_Engine_Util.Notification_Send(PORPOCHA,%''
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error in Change Request workflow',
    'RS',
    'The Change request workflow process has errored the following error:<br>Activity PORPOCHA has no performer',
    'Follow the steps from [1995413.1] to resolve the error.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');    
    
    
  add_signature(
   'Note1905401.1',
   'select  to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
        to_char(ias.end_date,''DD-MON-RR HH24:MI:SS'') end_date,
        ap.name||''/''||pa.instance_label Activity,
        ias.activity_status Status,
        ias.activity_result_code Result,
        ias.assigned_user assigned_user,
        ias.notification_id NID,
        ntf.status "Status",
        ias.action,
        ias.performed_by
    from    wf_item_activity_statuses ias,
            wf_process_activities pa,
            wf_activities ac,
            wf_activities ap,
            wf_items i,
            wf_notifications ntf,
            po_requisition_headers_all prh
    where   ias.item_type = ''##$$ITMTYPE$$##''
    and     ias.item_key  = ''##$$ITMKEY$$##''
    and     ias.process_activity    = pa.instance_id
    and     pa.activity_name        = ac.name
    and     pa.activity_item_type   = ac.item_type
    and     pa.process_name         = ap.name
    and     pa.process_item_type    = ap.item_type
    and     pa.process_version      = ap.version
    and     i.item_type             = ''##$$ITMTYPE$$##''
    and     i.item_key              = ias.item_key
    and     i.begin_date            >= ac.begin_date
    and     i.begin_date            < nvl(ac.end_date, i.begin_date+1)
    and     ntf.notification_id(+)  = ias.notification_id
    and     prh.wf_item_type        = i.item_type
    and     prh.wf_item_key         = i.item_key
    and     prh.authorization_status = ''IN PROCESS''
    and     ap.name                 = ''AME_APPROVAL_LIST_ROUTING''
    and     ias.activity_status     = ''NOTIFIED''
    and     ias.activity_result_code = ''#NULL''
    and    ((po_apprvl_analyzer_pkg.chk_pkg_body_version(''POR_AME_REQ_WF_PVT'', ''120.41.12010000.9'') >= 0
         and po_apprvl_analyzer_pkg.chk_pkg_body_version(''POR_AME_REQ_WF_PVT'', ''120.41.12010000.11'') < 0)
       or (po_apprvl_analyzer_pkg.chk_pkg_body_version(''POR_AME_REQ_WF_PVT'', ''120.77.12020000.8'') >= 0
         and po_apprvl_analyzer_pkg.chk_pkg_body_version(''POR_AME_REQ_WF_PVT'', ''120.77.12020000.13'') < 0))',
    'WFStat: Requisition stuck in "IN PROCESS"',
    'RS',
    'This requisition seems to be stuck in "IN PROCESS" status and the next approver might not have received the notification.',
    'This seems to be a know code issue. Follow the steps from [1905401.1] to resolve the error.',
    NULL,
    'FAILURE',
    'E',
    'N',
    p_include_in_dx_summary => 'Y');     
    
    
    add_signature(
   'WFSTAT_ERROR_PROCESS_ACTIVITY_STATUS',
   'SELECT to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
           ap.name||'' / ''||pa.instance_label "Process / Activity",
           ap.display_name "Process Name",
           ac.display_name "Activity Name",
           ias.activity_status Status,
           ias.activity_result_code Result,
           ias.assigned_user assigned_user,
           ias.notification_id NID,
           ntf.status "Status"
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities_vl ap,
         wf_items i,
         wf_notifications ntf
    WHERE ias.item_type = i.item_type
    AND   ias.item_key = i.item_key
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.parent_item_type = ''##$$ITMTYPE$$##''
    AND   i.parent_item_key = ''##$$ITMKEY$$##''
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ntf.notification_id(+) = ias.notification_id
    ORDER BY ias.begin_date, ias.execution_time',
    'WFStat: Error Process Activity Statuses',
    'RS',
    'Error Process Activity Statuses found for the combination of Item Type / Item Key',
    NULL,
    'No Error Process Activity Statuses found for the combination of Item Type / Item Key',
    'ALWAYS',
    'E',
    'RS');

  add_signature(
   'WFSTAT_ERROR_PROCESS_ACTIVITY_STATUS_HIST',
   'SELECT to_char(ias.begin_date,''DD-MON-RR HH24:MI:SS'') begin_date,
           ap.name||'' / ''||pa.instance_label "Process / Activity",
           ap.display_name "Process Name",
           ac.display_name "Activity Name",
           ias.activity_status Status,
           ias.activity_result_code Result,
           ias.assigned_user assigned_user,
           ias.notification_id NID,
           ntf.status "Status"
    FROM wf_item_activity_statuses_h ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities_vl ap,
         wf_items i,
         wf_notifications ntf
    WHERE ias.item_type = i.item_type
    AND   ias.item_key  = i.item_key
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.parent_item_type = ''##$$ITMTYPE$$##''
    AND   i.parent_item_key = ''##$$ITMKEY$$##''
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    AND   ntf.notification_id(+) = ias.notification_id
order by ias.begin_date, ias.execution_time',
    'WFStat: Error Process Activity Statuses History',
    'RS',
    'Error Process Activity Statuses History found for the combination of Item Type / Item Key',
    NULL,
    'No Error Process Activity Statuses History found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');

  add_signature(
   'WFSTAT_ERROR_PROCESS_ERRORED_ACTIVITIES',
   'SELECT ac.name||'' (''||ac.display_name||'')'' "Activity (Display Name)",
           ias.activity_result_code Result,
           ias.error_name ERROR_NAME,
           ias.error_message ERROR_MESSAGE,
           ias.error_stack ERROR_STACK
    FROM wf_item_activity_statuses ias,
         wf_process_activities pa,
         wf_activities_vl ac,
         wf_activities ap,
         wf_items i
    WHERE ias.item_type = i.item_type
    AND   ias.item_key = i.item_key
    AND   ias.activity_status = ''ERROR''
    AND   ias.process_activity = pa.instance_id
    AND   pa.activity_name = ac.name
    AND   pa.activity_item_type = ac.item_type
    AND   pa.process_name = ap.name
    AND   pa.process_item_type = ap.item_type
    AND   pa.process_version = ap.version
    AND   i.parent_item_type = ''##$$ITMTYPE$$##''
    AND   i.parent_item_key = ''##$$ITMKEY$$##''
    AND   i.begin_date >= ac.begin_date
    AND   i.begin_date < nvl(ac.end_date, i.begin_date+1)
    ORDER BY ias.execution_time',
    'WFStat: Error Process Errored Activities',
    'RS',
    'Error Process Errored Activities found for the combination of Item Type / Item Key',
    NULL,
    'No Error Process Errored Activities found for the combination of Item Type / Item Key',
    'ALWAYS',
    'E',
    'RS');

  add_signature(
   'WFSTAT_ITEM_ATTRIBUTE_VALUES',
   'SELECT wiav.name attr_name,
           wia.type value_type,
           nvl(wiav.text_value,
           nvl(to_char(wiav.number_value),
           to_char(wiav.date_value,''DD-MON-YYYY hh24:mi:ss''))) value
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia
    WHERE wiav.item_type = ''##$$ITMTYPE$$##''
    AND   wiav.item_key = ''##$$ITMKEY$$##''
    AND   wia.item_type(+) = wiav.item_type
    AND   wia.name(+) = wiav.name
    AND   wia.type(+) <> ''EVENT''',
    'WFStat: Item Attribute Values',
    'RS',
    'Item Attribute Values found for the combination of Item Type / Item Key',
    NULL,
    'No Item Attribute Values found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS',
    'N');

  add_signature(
   'WFSTAT_EVENT_DATATYPE_ITEM_ATTR_VALUES',
   'SELECT wiav.name attr_name,
           wiav.event_value.priority,
           wiav.event_value.send_date,
           wiav.event_value.receive_date,
           wiav.event_value.correlation_id,
           wiav.event_value.event_name,

           wiav.event_value.event_key,
           wiav.event_value.event_data,
           wiav.event_value.from_agent.name,
           wiav.event_value.to_agent.name,
           wiav.event_value.error_subscription,
           wiav.event_value.error_message,
           wiav.event_value.error_stack
    FROM wf_item_attribute_values wiav,
         wf_item_attributes wia
    WHERE wiav.item_type = ''##$$ITMTYPE$$##''
    AND   wiav.item_key  = ''##$$ITMKEY$$##''
    AND   wia.item_type  = wiav.item_type
    AND   wia.name       = wiav.name
    AND   wia.type       = ''EVENT'' ',
    'WFStat: Event Datatype Item Attribute Values',
    'RS',
    'The above Event Datatype Item Attribute Values have been found for the combination of Item Type / Item Key',
    NULL,
    'No Event Datatype Item Attribute Values found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');

  add_signature(
   'WFSTAT_ACTIVITY_ATTR_VALUES',
   'SELECT wa.display_name activity_name,
       wpa.instance_id act_id,
       wav.name        attr_name,
       wav.value_type,
       nvl(wav.text_value, nvl(to_char(wav.number_value),to_char(wav.date_value,''DD-MON-YYYY hh24:mi:ss''))) value
FROM   wf_item_activity_statuses wias,
       wf_process_activities     wpa,
       wf_items                  wi,
       wf_activity_attr_values   wav,
       wf_activities_vl          wa
    WHERE  wi.item_type = ''##$$ITMTYPE$$##''
AND    wi.item_key = ''##$$ITMKEY$$##''
AND    wias.item_type = wi.item_type
AND    wias.item_key = wi.item_key
AND    wias.process_activity = wpa.instance_id
AND    wav.process_activity_id = wpa.instance_id
AND    wpa.activity_name = wa.name
AND    wpa.activity_item_type = wa.item_type
AND    wa.begin_date <= wi.begin_date
AND    nvl(wa.end_date, sysdate) > wi.begin_date',
    'WFStat: Activity Attribute Values',
    'RS',
    'The above Activity Attribute Values found for the combination of Item Type / Item Key',
    NULL,
    'No Activity Attribute Values found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS');

  add_signature(
   'PO_WF_DEBUG',
   'SELECT wd.execution_sequence,
           wd.execution_date,
           wd.debug_message,
           wd.authorization_status
    FROM po_wf_debug wd
    WHERE wd.itemtype = ''##$$ITMTYPE$$##''
    AND   wd.itemkey  = ''##$$ITMKEY$$##''',
    'PO Workflow Debug Information',
    'RS',
    'The above debug messages have been found for the combination of Item Type / Item Key',
    NULL,
    'No debug messages found for the combination of Item Type / Item Key',
    'ALWAYS',
    'I',
    'RS',
    'N');

  /*#################################
    # Single Trx Document Details   #
    #################################*/

  ------------------------------------
  -- Display Trx Document Type Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_DOC_TYPE',
   'SELECT dt.type_name document_type,
           dt.org_id,
           dt.document_type_code,
           dt.document_subtype,
           dt.last_update_date,
           dt.last_updated_by,
           dt.forwarding_mode_code,
           dt.default_approval_path_id,
           dt.can_preparer_approve_flag "Preparer Can Approve",
           dt.can_change_approval_path_flag "Change Approval Path",
           dt.can_approver_modify_doc_flag "Approver Can Modify Doc",
           dt.can_change_forward_from_flag "Change Forward From",
           dt.can_change_forward_to_flag "Change Forward To",
           dt.wf_approval_itemtype,
           dt.wf_approval_process,
           dt.wf_createdoc_itemtype,
           dt.wf_createdoc_process,
           dt.ame_transaction_type,
           dt.archive_external_revision_code,
           dt.quotation_class_code,
           dt.security_level_code,
           dt.access_level_code,
           dt.disabled_flag,
           dt.ame_transaction_type,
           dt.use_contract_for_sourcing_flag,
           dt.include_noncatalog_flag,
           dt.document_template_code,
           dt.contract_template_code
    FROM po_document_types_all dt
    WHERE dt.document_type_code = ''##$$TRXTP$$##''
    AND   dt.document_subtype = ''##$$SUBTP$$##''
    AND   dt.org_id = ##$$ORGID$$##',
   'Document Type Details',
   'NRS',
   'No document type found for this document',
   'Verify that the document type and subtype are properly defined
    in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display PO Header Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_HEADER',
   'SELECT po_header_id header_id,
           segment1 po_number,
           approved_flag,
           approved_date,
           approval_required_flag,
           authorization_status,
           cancel_flag,
           org_id,
           submit_date,
           po_apprvl_analyzer_pkg.get_doc_amts(''NET_TOTAL'')
             document_net,
           po_apprvl_analyzer_pkg.get_doc_amts(''TAX'')
             document_tax,
           po_apprvl_analyzer_pkg.get_doc_amts(''TOTAL'')
             document_total,
           po_apprvl_analyzer_pkg.get_doc_amts(''PRECISION'')
             currency_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''EXT_PRECISION'')
             extended_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''MIN_ACCT_UNIT'')
             min_accountable_unit,
           summary_flag,
           enabled_flag,
           vendor_id,
           currency_code,
           rate_type,
           rate_date,
           rate,
           blanket_total_amount,
           authorization_status,
           revision_num,
           revised_date,
           amount_limit,
           min_release_amount,
           closed_date,
           approval_required_flag,
           interface_source_code,
           wf_item_type,
           wf_item_key,
           global_agreement_flag,
           encumbrance_required_flag,
           document_creation_method,
           style_id,
           creation_date,
           last_update_date,
           last_updated_by
    FROM po_headers_all
    WHERE po_header_id = ##$$DOCID$$##',
   'PO Header Details',
   'NRS',
   'No document header found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display PO Header Archive Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_HEADER_ARCHIVE',
   'SELECT po_header_id header_id,
           segment1 po_number,
           approved_flag,
           approved_date,
           approval_required_flag,
           authorization_status,
           cancel_flag,
           org_id,
           submit_date,
           po_apprvl_analyzer_pkg.get_doc_amts(''NET_TOTAL'')
             document_net,
           po_apprvl_analyzer_pkg.get_doc_amts(''TAX'')
             document_tax,
           po_apprvl_analyzer_pkg.get_doc_amts(''TOTAL'')
             document_total,
           po_apprvl_analyzer_pkg.get_doc_amts(''PRECISION'')
             currency_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''EXT_PRECISION'')
             extended_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''MIN_ACCT_UNIT'')
             min_accountable_unit,
           summary_flag,
           enabled_flag,
           vendor_id,
           currency_code,
           rate_type,
           rate_date,
           rate,
           blanket_total_amount,
           authorization_status,
           revision_num,
           revised_date,
           amount_limit,
           min_release_amount,
           closed_date,
           approval_required_flag,
           interface_source_code,
           wf_item_type,
           wf_item_key,
           global_agreement_flag,
           encumbrance_required_flag,
           document_creation_method,
           style_id,
           creation_date,
           last_update_date,
           last_updated_by
    FROM po_headers_archive_all
    WHERE po_header_id = ##$$DOCID$$##
      AND revision_num IN
          (SELECT max(revision_num) FROM po_headers_archive_all WHERE po_header_id = ##$$DOCID$$##)',
   'PO Header Archive Record (Highest Revision)',
   'NRS',
   'No document header archive found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');     
    
  ---------------------------------------------
  -- Display PO Style Details when AME is used
  ---------------------------------------------

  add_signature(
   'DOC_PO_STYLE_HEADER',
   'SELECT *
    FROM po_doc_style_headers
    ORDER BY style_name',
   'PO Style Header Details',
   'NRS',
   'The style header table data coult not be retrieved!',
   null,
   null,
   'ALWAYS',
   'I',
   'RS');   

  ------------------------------------
  -- Display Req Header Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REQ_HEADER',
   'SELECT requisition_header_id,
           segment1 doc_number,
           authorization_status approval_status,
           type_lookup_code requisition_type,
           authorization_status,
           approved_date,
           interface_source_code,
           org_id,
           po_apprvl_analyzer_pkg.get_doc_amts(''NET_TOTAL'')
             document_net,
           po_apprvl_analyzer_pkg.get_doc_amts(''TAX'')
             document_tax,
           po_apprvl_analyzer_pkg.get_doc_amts(''TOTAL'')
             document_total,
           po_apprvl_analyzer_pkg.get_doc_amts(''PRECISION'')
             currency_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''EXT_PRECISION'')
             extended_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''MIN_ACCT_UNIT'')
             min_accountable_unit,
           preparer_id,
           summary_flag,
           enabled_flag,
           closed_code,
           wf_item_type,
           wf_item_key,
           change_pending_flag,
           approved_date,
           first_approver_id,
           first_position_id,
           last_update_date,
           last_updated_by
    FROM po_requisition_headers_all
    WHERE requisition_header_id = ##$$DOCID$$##',
   'Requisition Header Details',
   'NRS',
   'No document header found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');


  ------------------------------------
  -- Display Release Header Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_HEADER',
   'SELECT r.po_release_id,
           r.po_header_id,
           p.segment1 po_number,
           r.release_num,
           r.revision_num,
           r.approved_flag,
           r.approved_date,
           r.authorization_status,
           r.cancel_flag,
           r.closed_code,
           r.release_type,
           r.document_creation_method,
           r.org_id,
           po_apprvl_analyzer_pkg.get_doc_amts(''NET_TOTAL'')
             document_net,
           po_apprvl_analyzer_pkg.get_doc_amts(''TAX'')
             document_tax,
           po_apprvl_analyzer_pkg.get_doc_amts(''TOTAL'')
             document_total,
           po_apprvl_analyzer_pkg.get_doc_amts(''PRECISION'')
             currency_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''EXT_PRECISION'')
             extended_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''MIN_ACCT_UNIT'')
             min_accountable_unit,
           r.release_date,
           r.agent_id,
           r.wf_item_type,
           r.wf_item_key,
           r.submit_date
    FROM po_releases_all r,
         po_headers_all p
    WHERE r.po_release_id = ##$$RELID$$##
    AND   r.po_header_id = p.po_header_id',
   'Release Header Details',
   'NRS',
   'No document header found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display Release Header Archive rec
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_HEADER_ARCHIVE',
   'SELECT r.po_release_id,
           r.po_header_id,
           p.segment1 po_number,
           r.release_num,
           r.revision_num,
           r.approved_flag,
           r.approved_date,
           r.authorization_status,
           r.cancel_flag,
           r.closed_code,
           r.release_type,
           r.document_creation_method,
           r.org_id,
           po_apprvl_analyzer_pkg.get_doc_amts(''NET_TOTAL'')
             document_net,
           po_apprvl_analyzer_pkg.get_doc_amts(''TAX'')
             document_tax,
           po_apprvl_analyzer_pkg.get_doc_amts(''TOTAL'')
             document_total,
           po_apprvl_analyzer_pkg.get_doc_amts(''PRECISION'')
             currency_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''EXT_PRECISION'')
             extended_precision,
           po_apprvl_analyzer_pkg.get_doc_amts(''MIN_ACCT_UNIT'')
             min_accountable_unit,
           r.release_date,
           r.agent_id,
           r.wf_item_type,
           r.wf_item_key,
           r.submit_date
    FROM po_releases_archive_all r,
         po_headers_all p
    WHERE r.po_release_id = ##$$RELID$$##
    AND   r.po_header_id = p.po_header_id
    AND r.revision_num IN
          (SELECT max(revision_num) FROM po_releases_archive_all WHERE po_release_id = ##$$RELID$$##)',
   'Release Header Archive Record (Highest Revision)',
   'NRS',
   'No document header found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display PO Line Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_LINES',
   'SELECT l.line_num,
           l.po_line_id,
           l.item_id,
           substr(msi.segment1,1,40) item_number,
           l.item_revision,
           l.item_description,
           l.category_id,
           mca.concatenated_segments item_category,
           lt.line_type,
           lt.outside_operation_flag,
           l.list_price_per_unit,
           l.unit_price,
           l.quantity,
           l.unit_meas_lookup_code,
           l.amount,
           l.taxable_flag,
           l.tax_name,
           l.closed_code,
           l.cancel_flag,
           l.closed_flag,
           l.cancelled_by,
           l.cancel_date,
           l.closed_code,
           l.not_to_exceed_price,
           l.allow_price_override_flag,
           l.price_break_lookup_code,
           l.tax_code_id,
           l.base_uom,
           l.base_qty,
           l.last_update_date,
           l.last_updated_by
    FROM po_lines_all l,
         po_line_types lt,
         mtl_system_items msi,
         financials_system_params_all fsp,
         mtl_categories_kfv mca
    WHERE l.po_header_id = ##$$DOCID$$##
    AND   fsp.org_id = l.org_id
    AND   msi.inventory_item_id (+) = l.item_id
    AND   nvl(msi.organization_id, fsp.inventory_organization_id) =
            fsp.inventory_organization_id
    AND   lt.line_type_id = l.line_type_id
    AND   mca.category_id  = l.category_id
    ORDER BY l.line_num',
   'PO Line Details',
   'NRS',
   'No document lines found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display PO Line Archive record
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_LINES_ARCHIVE',
   'SELECT l.line_num,
           l.po_line_id,
           l.item_id,
           substr(msi.segment1,1,40) item_number,
           l.item_revision,
           l.item_description,
           l.category_id,
           mca.concatenated_segments item_category,
           lt.line_type,
           lt.outside_operation_flag,
           l.list_price_per_unit,
           l.unit_price,
           l.quantity,
           l.unit_meas_lookup_code,
           l.amount,
           l.taxable_flag,
           l.tax_name,
           l.closed_code,
           l.cancel_flag,
           l.closed_flag,
           l.cancelled_by,
           l.cancel_date,
           l.closed_code,
           l.not_to_exceed_price,
           l.allow_price_override_flag,
           l.price_break_lookup_code,
           l.tax_code_id,
           l.base_uom,
           l.base_qty,
           l.last_update_date,
           l.last_updated_by
    FROM po_lines_archive_all l,
         po_line_types lt,
         mtl_system_items msi,
         financials_system_params_all fsp,
         mtl_categories_kfv mca
    WHERE l.po_header_id = ##$$DOCID$$##
    AND   fsp.org_id = l.org_id
    AND   msi.inventory_item_id (+) = l.item_id
    AND   nvl(msi.organization_id, fsp.inventory_organization_id) =
            fsp.inventory_organization_id
    AND   lt.line_type_id = l.line_type_id
    AND   mca.category_id  = l.category_id
    AND l.revision_num in
        (SELECT max(revision_num) from po_lines_archive_all where po_header_id = ##$$DOCID$$##)
    ORDER BY l.line_num',
   'PO Line Archive Details (Highest Revision)',
   'NRS',
   'No document lines found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'SUCCESS',
   'I',
   'RS',
   'N');   
   
   
   
  ------------------------------------
  -- Display Requisition Line Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REQ_LINES',
   'SELECT rl.line_num,
           rl.requisition_line_id,
           rl.item_id,
           rl.item_description,
           rl.category_id,
           mca.concatenated_segments item_category,
           lt.line_type,
           lt.outside_operation_flag,
           rl.unit_price,
           rl.quantity,
           rl.unit_meas_lookup_code uom,
           rl.amount,
           rl.currency_code,
           rl.currency_amount,
           rl.need_by_date,
           rl.encumbered_flag,
           p1.full_name requestor,
           rl.to_person_id,
           rl.rate,
           rl.rate_type,
           rl.rate_date,
           rl.currency_unit_price,
           p2.full_name suggested_buyer,
           rl.suggested_buyer_id,
           rl.closed_code,
           rl.closed_date,
           rl.cancel_flag,
           rl.line_location_id,
           rl.parent_req_line_id,
           rl.purchasing_agent_id,
           rl.document_type_code,
           rl.tax_name,
           rl.tax_user_override_flag,
           rl.tax_code_id
    FROM po_requisition_lines_all rl,
         per_all_people_f p1,
         per_all_people_f p2,
         po_line_types lt,
         mtl_categories_kfv mca
    WHERE requisition_header_id = ##$$DOCID$$##
    AND   p1.person_id = rl.to_person_id
    AND   trunc(sysdate) BETWEEN
            p1.effective_start_date AND p1.effective_end_date
    AND   p2.person_id (+) = rl.suggested_buyer_id
    AND   (p2.person_id is null OR
           trunc(sysdate) BETWEEN
             p2.effective_start_date AND p2.effective_end_date)
    AND   lt.line_type_id = rl.line_type_id
    AND   mca.category_id  = rl.category_id
    ORDER BY rl.line_num',
   'Requisition Line Details',
   'NRS',
   'No document lines found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display Release Source Line Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_LINES',
   'SELECT l.line_num,
           l.po_line_id,
           l.item_id,
           substr(msi.segment1,1,40) item_number,
           l.item_revision,
           l.item_description,
           l.category_id,
           mca.concatenated_segments item_category,
           lt.line_type,
           lt.outside_operation_flag,
           l.list_price_per_unit,
           l.unit_price,
           l.quantity,
           l.unit_meas_lookup_code,
           l.amount,
           l.taxable_flag,
           l.tax_name,
           l.closed_code,
           l.cancel_flag,
           l.closed_flag,
           l.cancelled_by,
           l.cancel_date,
           l.closed_code,
           l.not_to_exceed_price,
           l.allow_price_override_flag,
           l.price_break_lookup_code,
           l.tax_code_id,
           l.base_uom,
           l.base_qty,
           l.last_update_date,
           l.last_updated_by
    FROM po_lines_all l,
         po_line_types lt,
         mtl_system_items msi,
         financials_system_params_all fsp,
         mtl_categories_kfv mca
    WHERE l.po_header_id = ##$$DOCID$$##
    AND   l.po_line_id IN (
            SELECT ll.po_line_id FROM po_line_locations_all ll
            WHERE ll.po_release_id = ##$$RELID$$##)
    AND   fsp.org_id = l.org_id
    AND   msi.inventory_item_id (+) = l.item_id
    AND   nvl(msi.organization_id, fsp.inventory_organization_id) =
            fsp.inventory_organization_id
    AND   lt.line_type_id = l.line_type_id
    AND   mca.category_id  = l.category_id
    ORDER BY l.line_num',
   'Release Source Line Details',
   'NRS',
   'No document lines found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  -------------------------------------------
  -- Display Release Source Line Archive rec
  -------------------------------------------
  add_signature(
   'DOC_DETAIL_REL_LINES_ARCHIVE',
   'SELECT l.line_num,
           l.po_line_id,
           l.revision_num,
           l.item_id,
           substr(msi.segment1,1,40) item_number,
           l.item_revision,
           l.item_description,
           l.category_id,
           mca.concatenated_segments item_category,
           lt.line_type,
           lt.outside_operation_flag,
           l.list_price_per_unit,
           l.unit_price,
           l.quantity,
           l.unit_meas_lookup_code,
           l.amount,
           l.taxable_flag,
           l.tax_name,
           l.closed_code,
           l.cancel_flag,
           l.closed_flag,
           l.cancelled_by,
           l.cancel_date,
           l.closed_code,
           l.not_to_exceed_price,
           l.allow_price_override_flag,
           l.price_break_lookup_code,
           l.tax_code_id,
           l.base_uom,
           l.base_qty,
           l.last_update_date,
           l.last_updated_by
    FROM po_lines_archive_all l,
         po_line_types lt,
         mtl_system_items msi,
         financials_system_params_all fsp,
         mtl_categories_kfv mca
    WHERE l.po_header_id = ##$$DOCID$$##
    AND   l.po_line_id IN (
            SELECT ll.po_line_id FROM po_line_locations_all ll
            WHERE ll.po_release_id = ##$$RELID$$##)
    AND   fsp.org_id = l.org_id
    AND   msi.inventory_item_id (+) = l.item_id
    AND   nvl(msi.organization_id, fsp.inventory_organization_id) =
            fsp.inventory_organization_id
    AND   lt.line_type_id = l.line_type_id
    AND   mca.category_id  = l.category_id
    ORDER BY l.line_num',
   'Release Source Line Archive Record (Highest Revision)',
   'NRS',
   'No document lines found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');   

  ------------------------------------
  -- Display PO Line Location Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_LINE_LOCATIONS',
   'SELECT l.line_num po_line_num,
           ll.line_location_id,
           ll.shipment_num,
           ll.shipment_type,
           ll.quantity,
           ll.unit_meas_lookup_code uom,
           ll.price_override discounted_price,
           ll.taxable_flag,
           ll.tax_name,
           ll.tax_user_override_flag,
           ll.tax_code_id,
           ll.source_shipment_id,
           ll2.shipment_num source_shipment_num,
           ll.ship_to_organization_id,
           org.organization_code ship_to_organization_code,
           ll.ship_to_location_id,
           loc.location_code ship_to_location_code,
           ll.quantity_accepted,
           ll.quantity_billed,
           ll.quantity_cancelled,
           ll.quantity_received,
           ll.quantity_rejected,
           ll.amount,
           po_headers_sv3.get_currency_code(ll.po_header_id)
             currency_code,
           ll.last_accept_date,
           ll.need_by_date,
           ll.promised_date,
           ll.firm_status_lookup_code,
           ll.price_discount,
           ll.start_date,
           ll.end_date,
           ll.lead_time,
           ll.lead_time_unit,
           ll.terms_id,
           apt.name payment_terms_name,
           ll.freight_terms_lookup_code,
           ll.fob_lookup_code,

           ll.ship_via_lookup_code,
           ll.accrue_on_receipt_flag,
           ll.from_header_id,
           ll.from_line_id,
           ll.from_line_location_id,
           ll.encumbered_flag,
           ll.encumbered_date,
           ll.approved_flag,
           ll.approved_date,
           ll.closed_code,
           ll.cancel_flag,
           ll.cancel_date,
           ll.cancel_reason,
           ll.cancelled_by,
           ll.closed_flag,
           ll.closed_by,
           ll.closed_date,
           ll.closed_reason,
           ll.ussgl_transaction_code,
           ll.government_context,
           ll.match_option,
           ll.secondary_unit_of_measure,
           ll.secondary_quantity
    FROM po_line_locations_all ll,
         po_line_locations_all ll2,
         po_lines_all l,
         ap_terms apt,
         hr_locations_all_vl loc,
         org_organization_definitions org
    WHERE ll.po_header_id = ##$$DOCID$$##
    AND   l.po_line_id = ll.po_line_id
    AND   apt.term_id (+) = ll.terms_id
    AND   loc.location_id (+) = ll.ship_to_location_id
    AND   org.organization_id(+) = ll.ship_to_organization_id
    AND   ll2.line_location_id (+) = ll.source_shipment_id
    ORDER BY l.line_num',
   'PO Line Location Details',
   'NRS',
   'No line location records found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');


  ------------------------------------------
  -- Display PO Line Location Archive Record
  ------------------------------------------
  add_signature(
   'DOC_DETAIL_PO_LINE_LOCATIONS_ARCHIVE',
   'SELECT l.line_num po_line_num,
           ll.line_location_id,
           ll.shipment_num,
           ll.shipment_type,
           ll.quantity,
           ll.unit_meas_lookup_code uom,
           ll.price_override discounted_price,
           ll.taxable_flag,
           ll.tax_name,
           ll.tax_user_override_flag,
           ll.tax_code_id,
           ll.source_shipment_id,
           ll2.shipment_num source_shipment_num,
           ll.ship_to_organization_id,
           org.organization_code ship_to_organization_code,
           ll.ship_to_location_id,
           loc.location_code ship_to_location_code,
           ll.quantity_accepted,
           ll.quantity_billed,
           ll.quantity_cancelled,
           ll.quantity_received,
           ll.quantity_rejected,
           ll.amount,
           po_headers_sv3.get_currency_code(ll.po_header_id)
             currency_code,
           ll.last_accept_date,
           ll.need_by_date,
           ll.promised_date,
           ll.firm_status_lookup_code,
           ll.price_discount,
           ll.start_date,
           ll.end_date,
           ll.lead_time,
           ll.lead_time_unit,
           ll.terms_id,
           apt.name payment_terms_name,
           ll.freight_terms_lookup_code,
           ll.fob_lookup_code,
           ll.ship_via_lookup_code,
           ll.accrue_on_receipt_flag,
           ll.from_header_id,
           ll.from_line_id,
           ll.from_line_location_id,
           ll.encumbered_flag,
           ll.encumbered_date,
           ll.approved_flag,
           ll.approved_date,
           ll.closed_code,
           ll.cancel_flag,
           ll.cancel_date,
           ll.cancel_reason,
           ll.cancelled_by,
           ll.closed_flag,
           ll.closed_by,
           ll.closed_date,
           ll.closed_reason,
           ll.ussgl_transaction_code,
           ll.government_context,
           ll.match_option,
           ll.secondary_unit_of_measure,
           ll.secondary_quantity
    FROM po_line_locations_archive_all ll,
         po_line_locations_archive_all ll2,
         po_lines_all l,
         ap_terms apt,
         hr_locations_all_vl loc,
         org_organization_definitions org
    WHERE ll.po_header_id = ##$$DOCID$$##
    AND   l.po_line_id = ll.po_line_id
    AND   apt.term_id (+) = ll.terms_id
    AND   loc.location_id (+) = ll.ship_to_location_id
    AND   org.organization_id(+) = ll.ship_to_organization_id
    AND   ll2.line_location_id (+) = ll.source_shipment_id
    AND   ll.revision_num in
       (SELECT max (revision_num) FROM po_line_locations_archive_all where po_header_id = ##$$DOCID$$##)
    ORDER BY l.line_num',
   'PO Line Location Archive record (Highest Revision)',
   'NRS',
   'No line location records found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'SUCCESS',
   'I',
   'RS');
   
   
   l_dynamic_sql := '';
   IF g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION' THEN
       l_dynamic_sql := 
       'SELECT  
          CR.CHANGE_REQUEST_GROUP_ID,
          CR.CHANGE_REQUEST_ID,
          CR.INITIATOR,
          CR.ACTION_TYPE,
          USR.USER_NAME REQUESTOR,
          CR.REQUEST_REASON,
          CR.REQUEST_LEVEL,
          CR.REQUEST_STATUS,
          CR.DOCUMENT_TYPE,
          CR.DOCUMENT_HEADER_ID,
          CR.REF_PO_HEADER_ID,
          CR.DOCUMENT_NUM,
          CR.DOCUMENT_REVISION_NUM,
          CR.PO_RELEASE_ID,
          CR.REQUESTER_ID,
          CR.RESPONDED_BY,
          CR.RESPONSE_DATE,
          CR.RESPONSE_REASON
	    from po_change_requests cr,
             fnd_user usr
	    where cr.document_header_id = ''##$$DOCID$$##''
	    and cr.document_type = ''##$$DOCTYPESHORT$$##''
           AND cr.REQUEST_STATUS NOT IN (''ACCEPTED'', ''REJECTED'')     
	       AND cr.INITIATOR = ''REQUESTER''
           AND USR.USER_ID = CR.CREATED_BY';
   ELSIF g_sql_tokens('##$$TRXTP$$##') = 'RELEASE' THEN
       l_dynamic_sql := 
       'SELECT  
          CR.CHANGE_REQUEST_GROUP_ID,
          CR.CHANGE_REQUEST_ID,
          CR.INITIATOR,
          CR.ACTION_TYPE,
          USR.USER_NAME REQUESTOR,
          CR.REQUEST_REASON,
          CR.REQUEST_LEVEL,
          CR.REQUEST_STATUS,
          CR.DOCUMENT_TYPE,
          CR.DOCUMENT_HEADER_ID,
          CR.REF_PO_HEADER_ID,
          CR.DOCUMENT_NUM,
          CR.DOCUMENT_REVISION_NUM,
          CR.PO_RELEASE_ID,
          CR.REQUESTER_ID,
          CR.RESPONDED_BY,
          CR.RESPONSE_DATE,
          CR.RESPONSE_REASON
    	from po_change_requests cr,
             fnd_user usr
    	where 
           cr.po_release_id = ''##$$RELID$$##''
           AND cr.REQUEST_STATUS NOT IN (''ACCEPTED'', ''REJECTED'')     
    	   AND cr.INITIATOR = ''REQUESTER''
           AND USR.USER_ID = CR.CREATED_BY';
    ELSE             
       l_dynamic_sql := 
       'SELECT  
          CR.CHANGE_REQUEST_GROUP_ID,
          CR.CHANGE_REQUEST_ID,
          CR.INITIATOR,
          CR.ACTION_TYPE,
          USR.USER_NAME REQUESTOR,
          CR.REQUEST_REASON,
          CR.REQUEST_LEVEL,
          CR.REQUEST_STATUS,
          CR.DOCUMENT_TYPE,
          CR.DOCUMENT_HEADER_ID,
          CR.REF_PO_HEADER_ID,
          CR.DOCUMENT_NUM,
          CR.DOCUMENT_REVISION_NUM,
          CR.PO_RELEASE_ID,
          CR.REQUESTER_ID,
          CR.RESPONDED_BY,
          CR.RESPONSE_DATE,
          CR.RESPONSE_REASON
    	from po_change_requests cr,
             fnd_user usr
    	where 
           cr.document_header_id in
               (select document_header_id from po_change_requests where ref_po_header_id = ''##$$DOCID$$##'')
           AND cr.REQUEST_STATUS NOT IN (''ACCEPTED'', ''REJECTED'')     
    	   AND cr.INITIATOR = ''REQUESTER''
           AND USR.USER_ID = CR.CREATED_BY';
    END IF;       
     
  ---------------------------------------------
  -- Display Open Change Request lines (if any)
  ---------------------------------------------
  add_signature(
   'DOC_DISPLAY_OPEN_CHG_REQUESTS',
   l_dynamic_sql,
   'Open Change Requests for the document',
   'RS',
   'There are existing open change requests available for this document.',
   null,
   'No open change requests found for this document',
   'ALWAYS',
   'W',
   'RS');
   
   
  ------------------------------------------
  -- Workflow Processes Involved Without Children
  ------------------------------------------
  l_info.delete;
  add_signature(
   'Workflow Processes Involved Parent',
   'SELECT  distinct 
            wfi.item_type,         
			wfi.item_key,
			wfi.owner_role,
            wfi.begin_date, 
			wfi.end_date ,
            wf_fwkmon.getitemstatus(wfi.item_type, wfi.item_key, wfi.end_date, wfi.root_activity, wfi.root_activity_version) status			
	FROM    PO_CHANGE_REQUESTS poc,         
			WF_ITEMS wfi 
	WHERE   poc.document_type IN (''##$$DOCTYPESHORT$$##'') 
	AND     poc.document_num = ''##$$DOCNUM$$##''   
	AND     ( poc.wf_item_key = wfi.item_key 
	OR        poc.wf_item_key = wfi.parent_item_key ) 
	UNION ALL 
	SELECT  distinct ph.wf_item_type,         
			ph.wf_item_key, 
			wfi.owner_role,
            wfi.begin_date, wfi.end_date, 
            wf_fwkmon.getitemstatus(wfi.item_type, wfi.item_key, wfi.end_date, wfi.root_activity, wfi.root_activity_version) status			
	FROM    PO_CHANGE_REQUESTS poc1,        
			PO_CHANGE_REQUESTS poc2,        
			PO_HEADERS_ALL ph,
			WF_ITEMS wfi 
	WHERE   poc1.document_header_id = poc2.ref_po_header_id 
	AND     nvl(poc1.po_release_id,-1) = nvl(poc2.ref_po_release_id,-1) 
	AND     poc2.document_num = ''##$$DOCNUM$$##'' 
	AND     poc2.document_type = ''##$$DOCTYPESHORT$$##'' 
	AND     poc1.document_type = ''PO'' 
	AND     ph.po_header_id = poc1.document_header_id 
	AND     ( poc1.wf_item_key = wfi.item_key 
	OR        poc1.wf_item_key = wfi.parent_item_key ) 
	UNION ALL 
	SELECT  distinct rlh.wf_item_type,          
			rlh.wf_item_key, 
			wfi.owner_role,
            wfi.begin_date, wfi.end_date, 
            wf_fwkmon.getitemstatus(wfi.item_type, wfi.item_key, wfi.end_date, wfi.root_activity, wfi.root_activity_version) status						
	FROM    PO_CHANGE_REQUESTS poc1,         
			PO_CHANGE_REQUESTS poc2,         
			PO_RELEASES_ALL rlh,
			WF_ITEMS wfi 
	WHERE   poc1.document_header_id = poc2.ref_po_header_id 
	AND     nvl(poc1.po_release_id,-1) = nvl(poc2.ref_po_release_id,-1) 
	AND     poc2.document_num = ''##$$DOCNUM$$##'' 
	AND     poc2.document_type = ''##$$DOCTYPESHORT$$##''
	AND     poc1.document_type = ''RELEASE'' 
	AND     rlh.po_release_id = poc1.po_release_id
	AND     ( poc1.wf_item_key = wfi.item_key 
	OR        poc1.wf_item_key = wfi.parent_item_key )' ,
   'Related Workflow Processes',
   'NRS',
   'This shows the Workflow Processes related to the pending Change Requests',
   '<ul>
   <li>No action is needed as this is only informational</li>
   </ul>',
   null,
  'ALWAYS',
   'I',
   'Y',
   'N');        
      

  ------------------------------------
  -- Display REL Line Location Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_LINE_LOCATIONS',
   'SELECT ll.line_location_id,
           l.line_num source_line_num,
           ll.shipment_num,
           ll.shipment_type,
           ll.quantity,
           ll.unit_meas_lookup_code uom,
           ll.price_override discounted_price,
           ll.taxable_flag,
           ll.tax_name,
           ll.tax_user_override_flag,
           ll.tax_code_id,
           ll.source_shipment_id,
           ll2.shipment_num source_shipment_num,
           ll.ship_to_organization_id,
           org.organization_code ship_to_organization_code,
           ll.ship_to_location_id,
           loc.location_code ship_to_location_code,
           ll.quantity_accepted,
           ll.quantity_billed,
           ll.quantity_cancelled,
           ll.quantity_received,
           ll.quantity_rejected,
           ll.amount,
           po_headers_sv3.get_currency_code(ll.po_header_id)
             currency_code,
           ll.last_accept_date,
           ll.need_by_date,
           ll.promised_date,
           ll.firm_status_lookup_code,
           ll.price_discount,
           ll.start_date,
           ll.end_date,
           ll.lead_time,
           ll.lead_time_unit,
           ll.terms_id,
           apt.name payment_terms_name,
           ll.freight_terms_lookup_code,
           ll.fob_lookup_code,
           ll.ship_via_lookup_code,
           ll.accrue_on_receipt_flag,
           ll.from_header_id,
           ll.from_line_id,
           ll.from_line_location_id,
           ll.encumbered_flag,
           ll.encumbered_date,
           ll.approved_flag,
           ll.approved_date,
           ll.closed_code,
           ll.cancel_flag,
           ll.cancel_date,
           ll.cancel_reason,
           ll.cancelled_by,
           ll.closed_flag,
           ll.closed_by,
           ll.closed_date,
           ll.closed_reason,
           ll.ussgl_transaction_code,
           ll.government_context,
           ll.match_option,
           ll.secondary_unit_of_measure,
           ll.secondary_quantity
    FROM po_line_locations_all ll,
         po_line_locations_all ll2,
         po_lines_all l,
         ap_terms apt,
         hr_locations_all_vl loc,
         org_organization_definitions org
    WHERE ll.po_release_id = ##$$RELID$$##
    AND   l.po_line_id = ll.po_line_id
    AND   apt.term_id (+) = ll.terms_id
    AND   loc.location_id (+) = ll.ship_to_location_id
    AND   org.organization_id(+) = ll.ship_to_organization_id
    AND   ll2.line_location_id (+) = ll.source_shipment_id
    ORDER BY l.line_num',
   'Release Line Location Details',
   'NRS',
   'No line location records found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');


  ------------------------------------
  -- Display REL Line Location Archive rec
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_LINE_LOCATIONS_ARCHIVE',
   'SELECT ll.line_location_id,
           l.line_num source_line_num,
           ll.shipment_num,
           ll.shipment_type,
           ll.quantity,
           ll.unit_meas_lookup_code uom,
           ll.price_override discounted_price,
           ll.taxable_flag,
           ll.tax_name,
           ll.tax_user_override_flag,
           ll.tax_code_id,
           ll.source_shipment_id,
           ll2.shipment_num source_shipment_num,
           ll.ship_to_organization_id,
           org.organization_code ship_to_organization_code,
           ll.ship_to_location_id,
           loc.location_code ship_to_location_code,
           ll.quantity_accepted,
           ll.quantity_billed,
           ll.quantity_cancelled,
           ll.quantity_received,
           ll.quantity_rejected,
           ll.amount,
           po_headers_sv3.get_currency_code(ll.po_header_id)
             currency_code,
           ll.last_accept_date,
           ll.need_by_date,
           ll.promised_date,
           ll.firm_status_lookup_code,
           ll.price_discount,
           ll.start_date,
           ll.end_date,
           ll.lead_time,
           ll.lead_time_unit,
           ll.terms_id,
           apt.name payment_terms_name,
           ll.freight_terms_lookup_code,
           ll.fob_lookup_code,
           ll.ship_via_lookup_code,
           ll.accrue_on_receipt_flag,
           ll.from_header_id,
           ll.from_line_id,
           ll.from_line_location_id,
           ll.encumbered_flag,
           ll.encumbered_date,
           ll.approved_flag,
           ll.approved_date,
           ll.closed_code,
           ll.cancel_flag,
           ll.cancel_date,
           ll.cancel_reason,
           ll.cancelled_by,
           ll.closed_flag,
           ll.closed_by,
           ll.closed_date,
           ll.closed_reason,
           ll.ussgl_transaction_code,
           ll.government_context,
           ll.match_option,
           ll.secondary_unit_of_measure,
           ll.secondary_quantity
    FROM po_line_locations_archive_all ll,
         po_line_locations_archive_all ll2,
         po_lines_all l,
         ap_terms apt,
         hr_locations_all_vl loc,
         org_organization_definitions org
    WHERE ll.po_release_id = ##$$RELID$$##
    AND   l.po_line_id = ll.po_line_id
    AND   apt.term_id (+) = ll.terms_id
    AND   loc.location_id (+) = ll.ship_to_location_id
    AND   org.organization_id(+) = ll.ship_to_organization_id
    AND   ll2.line_location_id (+) = ll.source_shipment_id
    ORDER BY l.line_num',
   'Release Line Location Archive Record (Highest Revision)',
   'NRS',
   'No line location records found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

   

  ------------------------------------
  -- Display PO Distribution Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_PO_DISTS',
   'SELECT d.po_line_id,
           d.distribution_num,
           d.line_location_id,
           d.quantity_ordered,
           d.code_combination_id,
           substr(rtrim(g.segment1||''-''||g.segment2||''-''||
             g.segment3||''-''||g.segment4||''-''||
             g.segment5||''-''||g.segment6||''-''||
             g.segment7||''-''||g.segment8||''-''||
             g.segment9||''-''||g.segment10||''-''||
             g.segment11||''-''||g.segment12||''-''||
             g.segment13||''-''||g.segment14||''-''||
             g.segment15||''-''||g.segment16||''-''||
             g.segment17||''-''||g.segment18||''-''||
             g.segment19||''-''||g.segment20||''-''||
             g.segment21||''-''||g.segment22||''-''||
             g.segment23||''-''||g.segment24||''-''||
             g.segment25||''-''||g.segment26||''-''||
             g.segment27||''-''||g.segment28||''-''||
             g.segment29||''-''||g.segment30,''-''), 1, 100) charge_acct,
           creation_date,
           created_by,
           po_release_id,
           quantity_delivered,
           quantity_billed,
           quantity_cancelled,
           req_header_reference_num,
           req_line_reference_num,
           req_distribution_id,
           deliver_to_location_id,
           deliver_to_person_id,
           rate_date,
           rate,
           amount_billed,
           accrued_flag,
           encumbered_flag,
           encumbered_amount,
           unencumbered_quantity,
           unencumbered_amount,
           failed_funds_lookup_code,
           gl_encumbered_date,
           gl_encumbered_period_name,
           gl_cancelled_date,
           destination_type_code,
           destination_organization_id,
           destination_subinventory,
           budget_account_id,
           accrual_account_id,
           variance_account_id,
           prevent_encumbrance_flag,
           ussgl_transaction_code,
           government_context,
           destination_context,
           source_distribution_id,
           project_id,
           task_id,
           expenditure_type,
           project_accounting_context,
           expenditure_organization_id,
           gl_closed_date,
           accrue_on_receipt_flag,
           expenditure_item_date,
           mrc_rate_date,
           mrc_rate,
           mrc_encumbered_amount,
           mrc_unencumbered_amount,
           end_item_unit_number,
           tax_recovery_override_flag,
           recoverable_tax,
           nonrecoverable_tax,
           recovery_rate,
           oke_contract_line_id,
           oke_contract_deliverable_id,
           amount_ordered,
           amount_delivered,
           amount_cancelled,
           distribution_type,
           amount_to_encumber,
           invoice_adjustment_flag,
           dest_charge_account_id,
           dest_variance_account_id,
           quantity_financed,
           amount_financed,
           quantity_recouped,
           amount_recouped,
           retainage_withheld_amount,
           retainage_released_amount,
           wf_item_key,
           invoiced_val_in_ntfn,
           tax_attribute_update_code,
           interface_distribution_ref
    FROM po_distributions_all d,
         gl_code_combinations g
    WHERE d.po_header_id = ##$$DOCID$$##
    AND d.code_combination_id = g.code_combination_id(+)
    ORDER BY d.po_line_id, d.distribution_num',
   'PO Distribution Details',
   'NRS',
   'No distributions found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

   
  -----------------------------------------
  -- Display PO Distribution Archive Record
  -----------------------------------------
  add_signature(
   'DOC_DETAIL_PO_DISTS_ARCHIVE',
   'SELECT d.po_line_id,
           d.distribution_num,
           d.quantity_ordered,
           d.code_combination_id,
           substr(rtrim(g.segment1||''-''||g.segment2||''-''||
             g.segment3||''-''||g.segment4||''-''||
             g.segment5||''-''||g.segment6||''-''||
             g.segment7||''-''||g.segment8||''-''||
             g.segment9||''-''||g.segment10||''-''||
             g.segment11||''-''||g.segment12||''-''||
             g.segment13||''-''||g.segment14||''-''||
             g.segment15||''-''||g.segment16||''-''||
             g.segment17||''-''||g.segment18||''-''||
             g.segment19||''-''||g.segment20||''-''||
             g.segment21||''-''||g.segment22||''-''||
             g.segment23||''-''||g.segment24||''-''||
             g.segment25||''-''||g.segment26||''-''||
             g.segment27||''-''||g.segment28||''-''||
             g.segment29||''-''||g.segment30,''-''), 1, 100) charge_acct,
           creation_date,
           created_by,
           po_release_id,
           quantity_delivered,
           quantity_billed,
           quantity_cancelled,
           req_header_reference_num,
           req_line_reference_num,
           req_distribution_id,
           deliver_to_location_id,
           deliver_to_person_id,
           rate_date,
           rate,
           amount_billed,
           accrued_flag,
           encumbered_flag,
           encumbered_amount,
           unencumbered_quantity,
           unencumbered_amount,
           failed_funds_lookup_code,
           gl_encumbered_date,
           gl_encumbered_period_name,
           gl_cancelled_date,
           destination_type_code,
           destination_organization_id,
           destination_subinventory,
           budget_account_id,
           accrual_account_id,
           variance_account_id,
           prevent_encumbrance_flag,
           ussgl_transaction_code,
           government_context,
           destination_context,
           source_distribution_id,
           project_id,
           task_id,
           expenditure_type,
           project_accounting_context,
           expenditure_organization_id,
           gl_closed_date,
           accrue_on_receipt_flag,
           expenditure_item_date,
           mrc_rate_date,
           mrc_rate,
           mrc_encumbered_amount,
           mrc_unencumbered_amount,
           end_item_unit_number,
           tax_recovery_override_flag,
           recoverable_tax,
           nonrecoverable_tax,
           recovery_rate,
           oke_contract_line_id,
           oke_contract_deliverable_id,
           amount_ordered,
           amount_delivered,
           amount_cancelled,
           distribution_type,
           amount_to_encumber,
           invoice_adjustment_flag,
           dest_charge_account_id,
           dest_variance_account_id,
           quantity_financed,
           amount_financed,
           quantity_recouped,
           amount_recouped,
           retainage_withheld_amount,
           retainage_released_amount
    FROM po_distributions_archive_all d,
         gl_code_combinations g
    WHERE d.po_header_id = ##$$DOCID$$##
    AND d.code_combination_id = g.code_combination_id(+)
    AND d.revision_num IN
        (SELECT max(revision_num) FROM po_distributions_archive_all where po_header_id = ##$$DOCID$$##)
    ORDER BY d.po_line_id, d.distribution_num',
   'PO Distribution Archive (Highest Revision)',
   'NRS',
   'No distributions found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'SUCCESS',
   'I',
   'RS');
      
   
   
  -------------------------------------------
  -- Display Requisition Distribution Details
  -------------------------------------------
  add_signature(
   'DOC_DETAIL_REQ_DISTS',
   'SELECT d.requisition_line_id,
           d.distribution_num,
           d.req_line_quantity,
           d.code_combination_id,
           substr(rtrim(g.segment1||''-''||g.segment2||''-''||
             g.segment3||''-''||g.segment4||''-''||
             g.segment5||''-''||g.segment6||''-''||
             g.segment7||''-''||g.segment8||''-''||
             g.segment9||''-''||g.segment10||''-''||
             g.segment11||''-''||g.segment12||''-''||
             g.segment13||''-''||g.segment14||''-''||
             g.segment15||''-''||g.segment16||''-''||
             g.segment17||''-''||g.segment18||''-''||
             g.segment19||''-''||g.segment20||''-''||
             g.segment21||''-''||g.segment22||''-''||
             g.segment23||''-''||g.segment24||''-''||
             g.segment25||''-''||g.segment26||''-''||
             g.segment27||''-''||g.segment28||''-''||
             g.segment29||''-''||g.segment30,''-'') ,1,100) charge_acct,
           d.encumbered_flag,
           d.gl_encumbered_date,
           d.gl_encumbered_period_name,
           d.gl_cancelled_date,
           d.failed_funds_lookup_code,
           d.encumbered_amount,
           d.budget_account_id,
           d.accrual_account_id,
           d.variance_account_id,
           d.prevent_encumbrance_flag,
           d.ussgl_transaction_code,
           d.government_context,
           d.project_id,
           d.task_id,
           d.expenditure_type,
           d.project_accounting_context,
           d.expenditure_organization_id,
           d.gl_closed_date,
           d.source_req_distribution_id,
           d.allocation_type,
           d.allocation_value,
           d.project_related_flag,
           d.expenditure_item_date
    FROM po_req_distributions_all d,
         gl_code_combinations g
    WHERE d.requisition_line_id IN (
            SELECT pla.requisition_line_id
            FROM po_requisition_lines_all pla
            WHERE pla.requisition_header_id = ##$$DOCID$$## )
    AND   d.code_combination_id = g.code_combination_id(+)
    ORDER BY d.requisition_line_id, d.distribution_num',
   'Requisition Distribution Details',
   'NRS',
   'No distributions found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  ------------------------------------
  -- Display Release Distribution Details
  ------------------------------------
  add_signature(
   'DOC_DETAIL_REL_DISTS',
   'SELECT d.po_line_id,
           d.distribution_num,
           d.quantity_ordered,
           d.code_combination_id,
           substr(rtrim(g.segment1||''-''||g.segment2||''-''||
             g.segment3||''-''||g.segment4||''-''||
             g.segment5||''-''||g.segment6||''-''||
             g.segment7||''-''||g.segment8||''-''||
             g.segment9||''-''||g.segment10||''-''||
             g.segment11||''-''||g.segment12||''-''||
             g.segment13||''-''||g.segment14||''-''||
             g.segment15||''-''||g.segment16||''-''||
             g.segment17||''-''||g.segment18||''-''||
             g.segment19||''-''||g.segment20||''-''||
             g.segment21||''-''||g.segment22||''-''||
             g.segment23||''-''||g.segment24||''-''||
             g.segment25||''-''||g.segment26||''-''||
             g.segment27||''-''||g.segment28||''-''||
             g.segment29||''-''||g.segment30,''-'') ,1,100) charge_acct,
           d.creation_date,
           d.created_by,
           d.po_release_id,
           d.quantity_delivered,
           d.quantity_billed,
           d.quantity_cancelled,
           d.req_header_reference_num,
           d.req_line_reference_num,
           d.req_distribution_id,
           d.deliver_to_location_id,
           d.deliver_to_person_id,
           d.rate_date,
           d.rate,
           d.amount_billed,
           d.accrued_flag,
           d.encumbered_flag,
           d.encumbered_amount,
           d.unencumbered_quantity,
           d.unencumbered_amount,
           d.failed_funds_lookup_code,
           d.gl_encumbered_date,
           d.gl_encumbered_period_name,
           d.gl_cancelled_date,
           d.destination_type_code,
           d.destination_organization_id,
           d.destination_subinventory,
           d.budget_account_id,
           d.accrual_account_id,
           d.variance_account_id,
           d.prevent_encumbrance_flag,
           d.ussgl_transaction_code,
           d.government_context,
           d.destination_context,
           d.source_distribution_id,
           d.project_id,
           d.task_id,
           d.expenditure_type,
           d.project_accounting_context,
           d.expenditure_organization_id,
           d.gl_closed_date,
           d.accrue_on_receipt_flag,
           d.expenditure_item_date,
           d.mrc_rate_date,
           d.mrc_rate,
           d.mrc_encumbered_amount,
           d.mrc_unencumbered_amount,
           d.end_item_unit_number,
           d.tax_recovery_override_flag,
           d.recoverable_tax,
           d.nonrecoverable_tax,
           d.recovery_rate,
           d.oke_contract_line_id,
           d.oke_contract_deliverable_id,
           d.amount_ordered,
           d.amount_delivered,
           d.amount_cancelled,
           d.distribution_type,
           d.amount_to_encumber,
           d.invoice_adjustment_flag,
           d.dest_charge_account_id,
           d.dest_variance_account_id,
           d.quantity_financed,
           d.amount_financed,
           d.quantity_recouped,
           d.amount_recouped,
           d.retainage_withheld_amount,
           d.retainage_released_amount,
           d.wf_item_key,
           d.invoiced_val_in_ntfn,
           d.tax_attribute_update_code,
           d.interface_distribution_ref
    FROM po_distributions_all d,
         gl_code_combinations g
    WHERE d.po_release_id = ##$$RELID$$##
    AND   d.code_combination_id = g.code_combination_id(+)
    ORDER BY d.po_line_id, d.distribution_num',
   'Release Distribution Details',
   'NRS',
   'No distributions found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

  --------------------------------------------
  -- Display Release Distribution Archive rec
  --------------------------------------------
  add_signature(
   'DOC_DETAIL_REL_DISTS_ARCHIVE',
   'SELECT d.po_line_id,
           d.distribution_num,
           d.quantity_ordered,
           d.code_combination_id,
           substr(rtrim(g.segment1||''-''||g.segment2||''-''||
             g.segment3||''-''||g.segment4||''-''||
             g.segment5||''-''||g.segment6||''-''||
             g.segment7||''-''||g.segment8||''-''||
             g.segment9||''-''||g.segment10||''-''||
             g.segment11||''-''||g.segment12||''-''||
             g.segment13||''-''||g.segment14||''-''||
             g.segment15||''-''||g.segment16||''-''||
             g.segment17||''-''||g.segment18||''-''||
             g.segment19||''-''||g.segment20||''-''||
             g.segment21||''-''||g.segment22||''-''||
             g.segment23||''-''||g.segment24||''-''||
             g.segment25||''-''||g.segment26||''-''||
             g.segment27||''-''||g.segment28||''-''||
             g.segment29||''-''||g.segment30,''-'') ,1,100) charge_acct,
           d.creation_date,
           d.created_by,
           d.po_release_id,
           d.quantity_delivered,
           d.quantity_billed,
           d.quantity_cancelled,
           d.req_header_reference_num,
           d.req_line_reference_num,
           d.req_distribution_id,
           d.deliver_to_location_id,
           d.deliver_to_person_id,
           d.rate_date,
           d.rate,
           d.amount_billed,
           d.accrued_flag,
           d.encumbered_flag,
           d.encumbered_amount,
           d.unencumbered_quantity,
           d.unencumbered_amount,
           d.failed_funds_lookup_code,
           d.gl_encumbered_date,
           d.gl_encumbered_period_name,
           d.gl_cancelled_date,
           d.destination_type_code,
           d.destination_organization_id,
           d.destination_subinventory,
           d.budget_account_id,
           d.accrual_account_id,
           d.variance_account_id,
           d.prevent_encumbrance_flag,
           d.ussgl_transaction_code,
           d.government_context,
           d.destination_context,
           d.source_distribution_id,
           d.project_id,
           d.task_id,
           d.expenditure_type,
           d.project_accounting_context,
           d.expenditure_organization_id,
           d.gl_closed_date,
           d.accrue_on_receipt_flag,
           d.expenditure_item_date,
           d.mrc_rate_date,
           d.mrc_rate,
           d.mrc_encumbered_amount,
           d.mrc_unencumbered_amount,
           d.end_item_unit_number,
           d.tax_recovery_override_flag,
           d.recoverable_tax,
           d.nonrecoverable_tax,
           d.recovery_rate,
           d.oke_contract_line_id,
           d.oke_contract_deliverable_id,
           d.amount_ordered,
           d.amount_delivered,
           d.amount_cancelled,
           d.distribution_type,
           d.amount_to_encumber,
           d.invoice_adjustment_flag,
           d.dest_charge_account_id,
           d.dest_variance_account_id,
           d.quantity_financed,
           d.amount_financed,
           d.quantity_recouped,
           d.amount_recouped,
           d.retainage_withheld_amount,
           d.retainage_released_amount
    FROM po_distributions_archive_all d,
         gl_code_combinations g
    WHERE d.po_release_id = ##$$RELID$$##
    AND   d.code_combination_id = g.code_combination_id(+)
    ORDER BY d.po_line_id, d.distribution_num',
   'Release Distribution Archive Record (Highest Revision)',
   'NRS',
   'No distributions found for this document',
   'Verify that the document exists in this operating unit',
   null,
   'ALWAYS',
   'I',
   'RS');

   

  /*######################################
    #  Single Trx Data Integrity Checks  #
    ######################################*/

  l_info.delete;      
  -----------------------------------
  -- Single Trx Data Integrity PO 1
  -----------------------------------
  add_signature(
   'DATA_SINGLE_PO1',
   'SELECT h.segment1 po_number,
           h.type_lookup_code type_lookup_code,
           h.po_header_id,
           h.po_header_id "##$$FK1$$##",           
           h.revision_num,
           h.creation_date
    FROM po_headers_all h,
         po_headers_archive_all ha,
         po_acceptances a,
         po_document_types_all dt
    WHERE h.type_lookup_code in (''STANDARD'',''CONTRACT'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status = ''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code = dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num = ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.po_header_id = a.po_header_id(+)
    AND   a.revision_num (+) = h.revision_num
    AND   a.accepted_flag(+) = ''Y''
    AND   (((h.vendor_site_id <> ha.vendor_site_id) OR
           (h.vendor_site_id IS NULL AND ha.vendor_site_id IS NOT NULL) OR
           (h.vendor_site_id IS NOT NULL AND ha.vendor_site_id IS NULL)) OR
          ((h.vendor_contact_id <> ha.vendor_contact_id) OR
           (h.vendor_contact_id IS NULL AND ha.vendor_contact_id IS NOT NULL) OR
           (h.vendor_contact_id IS NOT NULL AND ha.vendor_contact_id IS NULL)) OR
          ((h.ship_to_location_id <> ha.ship_to_location_id) OR
           (h.ship_to_location_id IS NULL AND ha.ship_to_location_id IS NOT NULL) OR
           (h.ship_to_location_id IS NOT NULL AND ha.ship_to_location_id IS NULL)) OR
          ((h.bill_to_location_id <> ha.bill_to_location_id) OR
           (h.bill_to_location_id IS NULL AND ha.bill_to_location_id IS NOT NULL) OR
           (h.bill_to_location_id IS NOT NULL AND ha.bill_to_location_id IS NULL)) OR
          ((h.terms_id <> ha.terms_id) OR
           (h.terms_id IS NULL AND ha.terms_id IS NOT NULL) OR
           (h.terms_id IS NOT NULL AND ha.terms_id IS NULL)) OR
          ((h.ship_via_lookup_code <> ha.ship_via_lookup_code) OR
           (h.ship_via_lookup_code IS NULL AND ha.ship_via_lookup_code IS NOT NULL) OR
           (h.ship_via_lookup_code IS NOT NULL AND ha.ship_via_lookup_code IS NULL)) OR
          ((h.fob_lookup_code <> ha.fob_lookup_code) OR
           (h.fob_lookup_code IS NULL AND ha.fob_lookup_code IS NOT NULL) OR
           (h.fob_lookup_code IS NOT NULL AND ha.fob_lookup_code IS NULL)) OR
          ((h.freight_terms_lookup_code <> ha.freight_terms_lookup_code) OR
           (h.freight_terms_lookup_code IS NULL AND
            ha.freight_terms_lookup_code IS NOT NULL) OR
           (h.freight_terms_lookup_code IS NOT NULL AND
            ha.freight_terms_lookup_code IS NULL)) OR
          ((h.shipping_control <> ha.shipping_control) OR
           (h.shipping_control IS NULL AND ha.shipping_control IS NOT NULL) OR
           (h.shipping_control IS NOT NULL AND ha.shipping_control IS NULL)) OR
          ((h.blanket_total_amount <> ha.blanket_total_amount) OR
           (h.blanket_total_amount IS NULL AND ha.blanket_total_amount IS NOT NULL) OR
           (h.blanket_total_amount IS NOT NULL AND ha.blanket_total_amount IS NULL)) OR
          ((h.note_to_vendor <> ha.note_to_vendor) OR
           (h.note_to_vendor IS NULL AND ha.note_to_vendor IS NOT NULL) OR
           (h.note_to_vendor IS NOT NULL AND ha.note_to_vendor IS NULL)) OR
          ((h.confirming_order_flag <> ha.confirming_order_flag) OR
           (h.confirming_order_flag IS NULL AND ha.confirming_order_flag IS NOT NULL) OR
           (h.confirming_order_flag IS NOT NULL AND ha.confirming_order_flag IS NULL)) OR
          (((h.acceptance_required_flag <> ha.acceptance_required_flag) AND
            (h.acceptance_required_flag <> ''N'')) OR
           (ha.acceptance_required_flag in (''Y'',''D'') AND
            h.acceptance_required_flag = ''N'' AND
            (nvl(a.accepted_flag,''X'') <> ''Y'')) OR
           (h.acceptance_required_flag IS NULL AND
            ha.acceptance_required_flag IS NOT NULL) OR
           (h.acceptance_required_flag IS NOT NULL AND
            ha.acceptance_required_flag IS NULL)) OR
          ((h.acceptance_due_date <> ha.acceptance_due_date) OR
           (h.acceptance_due_date IS NULL AND ha.acceptance_due_date IS NOT NULL AND
            nvl(a.accepted_flag,''N'') = ''N'' AND
            nvl(h.acceptance_required_flag, ''X'') <> ''S'') OR
           (h.acceptance_due_date IS NOT NULL AND ha.acceptance_due_date IS NULL)) OR
          ((h.amount_limit <> ha.amount_limit) OR
           (h.amount_limit IS NULL AND ha.amount_limit IS NOT NULL) OR
           (h.amount_limit IS NOT NULL AND ha.amount_limit IS NULL)) OR
          ((h.start_date <> ha.start_date) OR
           (h.start_date IS NULL AND ha.start_date IS NOT NULL) OR
           (h.start_date IS NOT NULL AND ha.start_date IS NULL)) OR
          ((h.end_date <> ha.end_date) OR
           (h.end_date IS NULL AND ha.end_date IS NOT NULL) OR
           (h.end_date IS NOT NULL AND ha.end_date IS NULL)) OR
          ((h.cancel_flag <> ha.cancel_flag) OR
           (h.cancel_flag IS NULL AND ha.cancel_flag IS NOT NULL) OR
           (h.cancel_flag IS NOT NULL AND ha.cancel_flag IS NULL)) OR
          ((h.conterms_articles_upd_date <> ha.conterms_articles_upd_date) OR
           (h.conterms_articles_upd_date IS NULL AND
            ha.conterms_articles_upd_date IS NOT NULL) OR
           (h.conterms_articles_upd_date IS NOT NULL AND
            ha.conterms_articles_upd_date IS NULL)) OR
          ((h.conterms_deliv_upd_date <> ha.conterms_deliv_upd_date) OR
           (h.conterms_deliv_upd_date IS NULL AND
            ha.conterms_deliv_upd_date IS NOT NULL) OR
           (h.conterms_deliv_upd_date IS NOT NULL AND
            ha.conterms_deliv_upd_date IS NULL)))
    AND   h.po_header_id = ##$$DOCID$$##',
    'Synchronization Issues with Headers Archive',
    'RS',
    'There are data discrepancies between PO_HEADERS_ALL and PO_HEADERS_ARCHIVE_ALL
     for this PO, which can result in issues trying to cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_PO1'),
    p_include_in_dx_summary => 'Y');
    
    l_info.delete;  
 
  ---------------------------------------
  -- Child Single Trx Data Integrity PO 1
  ---------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_PO1',
   'SELECT poh.po_header_id,
           (DECODE(poh.Agent_id,poha.Agent_id,NULL,poh.Agent_id
           ||''-->''
           ||poha.Agent_id)) Agent_id,
           (DECODE(poh.vendor_site_id,poha.vendor_site_id,NULL,poh.vendor_site_id
           ||''-->''
           ||poha.vendor_site_id)) vendor_site_id,
           (DECODE(poh.vendor_contact_id,poha.vendor_contact_id,NULL,poh.vendor_contact_id
           ||''-->''
           ||poha.vendor_contact_id)) vendor_contact_id,
           (DECODE(poh.ship_to_location_id ,poha.ship_to_location_id ,NULL,poh.ship_to_location_id
           ||''-->''
           ||poha.ship_to_location_id)) ship_to_location_id ,
           (DECODE(poh.bill_to_location_id ,poha.bill_to_location_id ,NULL,poh.bill_to_location_id
           ||''-->''
           ||poha.bill_to_location_id)) bill_to_location_id ,
           (DECODE(poh.terms_id ,poha.terms_id ,NULL,poh.terms_id
           ||''-->''
           ||poha.terms_id)) terms_id ,
           (DECODE(poh.ship_via_lookup_code ,poha.ship_via_lookup_code ,NULL,poh.ship_via_lookup_code
           ||''-->''
           ||poha.ship_via_lookup_code)) ship_via_lookup_code ,
           (DECODE(poh.fob_lookup_code ,poha.fob_lookup_code ,NULL,poh.fob_lookup_code
           ||''-->''
           ||poha.fob_lookup_code)) fob_lookup_code ,
           (DECODE(poh.freight_terms_lookup_code ,poha.freight_terms_lookup_code ,NULL,poh.freight_terms_lookup_code
           ||''-->''
           ||poha.freight_terms_lookup_code)) freight_terms_lookup_code ,
           (DECODE(poh.shipping_control ,poha.shipping_control ,NULL,poh.shipping_control
           ||''-->''
           ||poha.shipping_control)) shipping_control ,
           (DECODE(poh.blanket_total_amount ,poha.blanket_total_amount ,NULL,poh.blanket_total_amount
           ||''-->''
           ||poha.blanket_total_amount)) blanket_total_amount ,
           (DECODE(poh.note_to_vendor ,poha.note_to_vendor ,NULL,poh.note_to_vendor
           ||''-->''
           ||poha.note_to_vendor)) note_to_vendor ,
           (DECODE(poh.confirming_order_flag ,poha.confirming_order_flag ,NULL,poh.confirming_order_flag
           ||''-->''
           ||poha.confirming_order_flag)) confirming_order_flag ,
           (DECODE(poh.acceptance_required_flag ,poha.acceptance_required_flag ,NULL,poh.acceptance_required_flag
           ||''-->''
           ||poha.acceptance_required_flag)) acceptance_required_flag ,
           (DECODE(poh.acceptance_due_date ,poha.acceptance_due_date ,NULL,poh.acceptance_due_date
           ||''-->''
           ||poha.acceptance_due_date)) acceptance_due_date ,
           (DECODE(poh.amount_limit ,poha.amount_limit ,NULL,poh.amount_limit
           ||''-->''
           ||poha.amount_limit)) amount_limit ,
           (DECODE(poh.start_date ,poha.start_date ,NULL,poh.start_date
           ||''-->''
           ||poha.start_date)) start_date ,
           (DECODE(poh.end_date ,poha.end_date ,NULL,poh.end_date
           ||''-->''
           ||poha.end_date)) end_date ,
           (DECODE(poh.cancel_flag ,poha.cancel_flag ,NULL,poh.cancel_flag
           ||''-->''
           ||poha.cancel_flag)) cancel_flag ,
           (DECODE(poh.conterms_articles_upd_date ,poha.conterms_articles_upd_date ,NULL,poh.conterms_articles_upd_date
           ||''-->''
           ||poha.conterms_articles_upd_date)) conterms_articles_upd_date ,
           (DECODE(poh.conterms_deliv_upd_date ,poha.conterms_deliv_upd_date ,NULL,poh.conterms_deliv_upd_date
           ||''-->''
           ||poha.conterms_deliv_upd_date)) conterms_deliv_upd_date
           FROM PO_HEADERS_ALL POH,
             PO_HEADERS_ARCHIVE_ALL POHA,
             po_acceptances pa
           WHERE poh.po_header_id=##$$FK1$$##
              AND poh.type_lookup_code                   IN (''STANDARD'',''CONTRACT'',''PLANNED'',''BLANKET'')
              AND NVL(poh.closed_code,''OPEN'') NOT        IN (''FINALLY CLOSED'')
              AND NVL(poh.cancel_flag,''N'')               <> ''Y''
              AND POH.po_header_id                        = POHA.po_header_id
              AND POHA.latest_external_flag               = ''Y''
              AND poh.po_header_id                        =pa.po_header_id(+)
              AND pa.revision_num (+)                     = poh.revision_num
              AND pa.accepted_flag(+)                     =''Y''
              AND ( (POH.agent_id                        <> POHA.agent_id)
                    OR (POH.vendor_site_id                     <> POHA.vendor_site_id)
                    OR (POH.vendor_site_id                     IS NULL
                    AND POHA.vendor_site_id                    IS NOT NULL)
                    OR (POH.vendor_site_id                     IS NOT NULL
                    AND POHA.vendor_site_id                    IS NULL)
                    OR (POH.vendor_contact_id                  <> POHA.vendor_contact_id)
                    OR (POH.vendor_contact_id                  IS NULL
                    AND POHA.vendor_contact_id                 IS NOT NULL)
                    OR (POH.vendor_contact_id                  IS NOT NULL
                    AND POHA.vendor_contact_id                 IS NULL)
                    OR (POH.ship_to_location_id                <> POHA.ship_to_location_id)
                    OR (POH.ship_to_location_id                IS NULL
                    AND POHA.ship_to_location_id               IS NOT NULL)
                    OR (POH.ship_to_location_id                IS NOT NULL
                    AND POHA.ship_to_location_id               IS NULL)
                    OR (POH.bill_to_location_id                <> POHA.bill_to_location_id)
                    OR (POH.bill_to_location_id                IS NULL
                    AND POHA.bill_to_location_id               IS NOT NULL)
                    OR (POH.bill_to_location_id                IS NOT NULL
                    AND POHA.bill_to_location_id               IS NULL)
                    OR (POH.terms_id                           <> POHA.terms_id)
                    OR (POH.terms_id                           IS NULL
                    AND POHA.terms_id                          IS NOT NULL)
                    OR (POH.terms_id                           IS NOT NULL
                    AND POHA.terms_id                          IS NULL)
                    OR (POH.ship_via_lookup_code               <> POHA.ship_via_lookup_code)
                    OR (POH.ship_via_lookup_code               IS NULL
                    AND POHA.ship_via_lookup_code              IS NOT NULL)
                    OR (POH.ship_via_lookup_code               IS NOT NULL
                    AND POHA.ship_via_lookup_code              IS NULL)
                    OR (POH.fob_lookup_code                    <> POHA.fob_lookup_code)
                    OR (POH.fob_lookup_code                    IS NULL
                    AND POHA.fob_lookup_code                   IS NOT NULL)
                    OR (POH.fob_lookup_code                    IS NOT NULL
                    AND POHA.fob_lookup_code                   IS NULL)
                    OR (POH.freight_terms_lookup_code          <> POHA.freight_terms_lookup_code)
                    OR (POH.freight_terms_lookup_code          IS NULL
                    AND POHA.freight_terms_lookup_code         IS NOT NULL)
                    OR (POH.freight_terms_lookup_code          IS NOT NULL
                    AND POHA.freight_terms_lookup_code         IS NULL)
                    OR (POH.shipping_control                   <> POHA.shipping_control)
                    OR (POH.shipping_control                   IS NULL
                    AND POHA.shipping_control                  IS NOT NULL)
                    OR (POH.shipping_control                   IS NOT NULL
                    AND POHA.shipping_control                  IS NULL)
                    OR (POH.blanket_total_amount               <> POHA.blanket_total_amount)
                    OR (POH.blanket_total_amount               IS NULL
                    AND POHA.blanket_total_amount              IS NOT NULL)
                    OR (POH.blanket_total_amount               IS NOT NULL
                    AND POHA.blanket_total_amount              IS NULL)
                    OR (POH.note_to_vendor                     <> POHA.note_to_vendor)
                    OR (POH.note_to_vendor                     IS NULL
                    AND POHA.note_to_vendor                    IS NOT NULL)
                    OR (POH.note_to_vendor                     IS NOT NULL
                    AND POHA.note_to_vendor                    IS NULL)
                    OR (POH.confirming_order_flag              <> POHA.confirming_order_flag)
                    OR (POH.confirming_order_flag              IS NULL
                    AND POHA.confirming_order_flag             IS NOT NULL)
                    OR (POH.confirming_order_flag              IS NOT NULL
                    AND POHA.confirming_order_flag             IS NULL)
                    OR ((POH.acceptance_required_flag          <> POHA.acceptance_required_flag)
                    AND (POH.acceptance_required_flag          <> ''N''))
                    OR (POHA.acceptance_required_flag          IN (''Y'',''D'')
                    AND POH.acceptance_required_flag            =''N''
                    AND (NVL(pa.accepted_flag,''X'')             <> ''Y''))
                    OR (POH.acceptance_required_flag           IS NULL
                    AND POHA.acceptance_required_flag          IS NOT NULL)
                    OR (POH.acceptance_required_flag           IS NOT NULL
                    AND POHA.acceptance_required_flag          IS NULL)
                    OR (POH.acceptance_due_date                <> POHA.acceptance_due_date)
                    OR (POH.acceptance_due_date                IS NULL
                    AND POHA.acceptance_due_date               IS NOT NULL
                    AND NVL(pa.accepted_flag,''N'')               =''N''
                    AND NVL(POH.acceptance_required_flag, ''X'') <> ''S'')
                    OR (POH.acceptance_due_date                IS NOT NULL
                    AND POHA.acceptance_due_date               IS NULL)
                    OR (POH.amount_limit                       <> POHA.amount_limit)
                    OR (POH.amount_limit                       IS NULL
                    AND POHA.amount_limit                      IS NOT NULL)
                    OR (POH.amount_limit                       IS NOT NULL
                    AND POHA.amount_limit                      IS NULL)
                    OR (POH.start_date                         <> POHA.start_date)
                    OR (POH.start_date                         IS NULL
                    AND POHA.start_date                        IS NOT NULL)
                    OR (POH.start_date                         IS NOT NULL
                    AND POHA.start_date                        IS NULL)
                    OR (POH.end_date                           <> POHA.end_date)
                    OR (POH.end_date                           IS NULL
                    AND POHA.end_date                          IS NOT NULL)
                    OR (POH.end_date                           IS NOT NULL
                    AND POHA.end_date                          IS NULL)
                    OR (POH.cancel_flag                        <> POHA.cancel_flag)
                    OR (POH.cancel_flag                        IS NULL
                    AND POHA.cancel_flag                       IS NOT NULL)
                    OR (POH.cancel_flag                        IS NOT NULL
                    AND POHA.cancel_flag                       IS NULL)
                    OR (POH.conterms_articles_upd_date         <> POHA.conterms_articles_upd_date)
                    OR (POH.conterms_articles_upd_date         IS NULL
                    AND POHA.conterms_articles_upd_date        IS NOT NULL)
                    OR (POH.conterms_articles_upd_date         IS NOT NULL
                    AND POHA.conterms_articles_upd_date        IS NULL)
                    OR (POH.conterms_deliv_upd_date            <> POHA.conterms_deliv_upd_date)
                    OR (POH.conterms_deliv_upd_date            IS NULL
                    AND POHA.conterms_deliv_upd_date           IS NOT NULL)
                    OR (POH.conterms_deliv_upd_date            IS NOT NULL
                    AND POHA.conterms_deliv_upd_date           IS NULL) )
              ORDER BY POH.po_header_id DESC',
   'PO_HEADERS_ALL - differences between the main table and the archive table:',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');   

  -----------------------------------
  -- Single Trx Data Integrity PO 2
  -----------------------------------
  add_signature(
   'DATA_SINGLE_PO2',
   'SELECT h.segment1 PO_NUMBER,
           h.type_lookup_code type_lookup_code,
           l.po_header_id,
           l.po_header_id "##$$FK1$$##",          
           l.po_line_id ,
           h.revision_num,
           l.line_num,
           la.base_unit_price,
           l.creation_date,
           l.last_update_date
    FROM po_lines_all l,
         po_lines_archive_all la,
         po_headers_all h ,
         po_headers_archive_all ha ,
         po_document_types_all dt
    WHERE h.po_header_id=l.po_header_id
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status=''APPROVED''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   l.po_line_id = la.po_line_id
    AND   la.latest_external_flag  = ''Y''
    AND   ((l.line_num <> la.line_num) OR
           ((l.item_id <> la.item_id) OR
            (l.item_id IS NULL AND la.item_id IS NOT NULL) OR
            (l.item_id IS NOT NULL AND   la.item_id IS NULL)) OR
           ((l.job_id <> la.job_id) OR
            (l.job_id IS NULL AND la.job_id IS NOT NULL) OR
            (l.job_id IS NOT NULL AND la.job_id IS NULL)) OR
           ((l.amount <> la.amount) OR
            (l.amount IS NULL AND la.amount IS NOT NULL) OR
            (l.amount IS NOT NULL AND la.amount IS NULL)) OR
           ((trunc(l.expiration_date) <> trunc(la.expiration_date)) OR
            (l.expiration_date IS NULL AND la.expiration_date IS NOT NULL) OR
            (l.expiration_date IS NOT NULL AND   la.expiration_date IS NULL)) OR
           ((trunc(l.start_date) <> trunc(la.start_date)) OR
            (l.start_date IS NULL AND la.start_date IS NOT NULL) OR
            (l.start_date IS NOT NULL AND la.start_date IS NULL)) OR
           ((l.contractor_first_name <> la.contractor_first_name) OR
            (l.contractor_first_name IS NULL AND la.contractor_first_name IS NOT NULL) OR
            (l.contractor_first_name IS NOT NULL AND la.contractor_first_name IS NULL)) OR
           ((l.contractor_last_name <> la.contractor_last_name) OR
            (l.contractor_last_name IS NULL AND la.contractor_last_name IS NOT NULL) OR
            (l.contractor_last_name IS NOT NULL AND la.contractor_last_name IS NULL)) OR
           ((l.item_revision <> la.item_revision) OR
            (l.item_revision IS NULL AND la.item_revision IS NOT NULL) OR
            (l.item_revision IS NOT NULL AND la.item_revision IS NULL)) OR
           ((l.item_description <> la.item_description) OR
            (l.item_description IS NULL AND la.item_description IS NOT NULL) OR
            (l.item_description IS NOT NULL AND la.item_description IS NULL)) OR
           ((l.unit_meas_lookup_code <> la.unit_meas_lookup_code) OR
            (l.unit_meas_lookup_code IS NULL AND la.unit_meas_lookup_code IS NOT NULL) OR
            (l.unit_meas_lookup_code IS NOT NULL AND la.unit_meas_lookup_code IS NULL)) OR
           ((l.quantity <> la.quantity) OR
            (l.quantity IS NULL AND la.quantity IS NOT NULL) OR
            (l.quantity IS NOT NULL AND la.quantity IS NULL)) OR
           ((l.quantity_committed <> la.quantity_committed) OR
            (l.quantity_committed IS NULL AND la.quantity_committed IS NOT NULL) OR
            (l.quantity_committed IS NOT NULL AND la.quantity_committed IS NULL)) OR
           ((l.committed_amount <> la.committed_amount) OR
            (l.committed_amount IS NULL AND la.committed_amount IS NOT NULL) OR
            (l.committed_amount IS NOT NULL AND la.committed_amount IS NULL)) OR
           ((l.unit_price <> la.unit_price) OR
            (l.unit_price IS NULL AND la.unit_price IS NOT NULL) OR
            (l.unit_price IS NOT NULL AND la.unit_price IS NULL)) OR
           ((l.not_to_exceed_price <> la.not_to_exceed_price) OR
            (l.not_to_exceed_price IS NULL AND la.not_to_exceed_price IS NOT NULL) OR
            (l.not_to_exceed_price IS NOT NULL AND la.not_to_exceed_price IS NULL)) OR
           ((l.un_number_id <> la.un_number_id) OR
            (l.un_number_id IS NULL AND la.un_number_id IS NOT NULL) OR
            (l.un_number_id IS NOT NULL AND la.un_number_id IS NULL)) OR
           ((l.hazard_class_id <> la.hazard_class_id) OR
            (l.hazard_class_id IS NULL AND la.hazard_class_id IS NOT NULL) OR
            (l.hazard_class_id IS NOT NULL AND la.hazard_class_id IS NULL)) OR
           ((l.note_to_vendor <> la.note_to_vendor) OR
            (l.note_to_vendor IS NULL AND la.note_to_vendor IS NOT NULL) OR
            (l.note_to_vendor IS NOT NULL AND la.note_to_vendor IS NULL)) OR
           ((l.note_to_vendor <> la.note_to_vendor) OR
            (l.note_to_vendor IS NULL AND la.note_to_vendor IS NOT NULL) OR
            (l.note_to_vendor IS NOT NULL AND la.note_to_vendor IS NULL)) OR
           ((l.from_header_id <> la.from_header_id) OR
            (l.from_header_id IS NULL AND la.from_header_id IS NOT NULL) OR
            (l.from_header_id IS NOT NULL AND la.from_header_id IS NULL)) OR
           ((l.from_line_id <> la.from_line_id) OR
            (l.from_line_id IS NULL AND la.from_line_id IS NOT NULL) OR
            (l.from_line_id IS NOT NULL AND la.from_line_id IS NULL)) OR
           ((l.vendor_product_num <> la.vendor_product_num) OR
            (l.vendor_product_num IS NULL AND la.vendor_product_num IS NOT NULL) OR
            (l.vendor_product_num IS NOT NULL AND la.vendor_product_num IS NULL)) OR
           ((l.contract_id <> la.contract_id) OR
            (l.contract_id IS NULL AND la.contract_id IS NOT NULL) OR
            (l.contract_id IS NOT NULL AND la.contract_id IS NULL)) OR
           ((l.price_type_lookup_code <> la.price_type_lookup_code) OR
            (l.price_type_lookup_code IS NULL AND
             la.price_type_lookup_code IS NOT NULL) OR
            (l.price_type_lookup_code IS NOT NULL AND
             la.price_type_lookup_code IS NULL)) OR
           ((l.cancel_flag <> la.cancel_flag) OR
            (l.cancel_flag IS NULL AND la.cancel_flag IS NOT NULL) OR
            (l.cancel_flag IS NOT NULL AND la.cancel_flag IS NULL)))
    AND   h.po_header_id = ##$$DOCID$$##',
    'Synchronization Issues with Lines Archive',
    'RS',
    'There are data discrepancies between PO_LINES_ALL and PO_LINES_ARCHIVE_ALL
     for this PO, which can result in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_PO2'),
    p_include_in_dx_summary => 'Y');
   
    l_info.delete;   
  ---------------------------------------
  -- Child Single Trx Data Integrity PO 2
  ---------------------------------------
    
   add_signature(
   'CHILD_DATA_SINGLE_PO2',
   'SELECT pol.po_header_id,
           POL.po_line_id,
           (DECODE(pol.line_num ,pola.line_num , NULL,pol.line_num
           ||''-->''
           ||pola.line_num )) line_num,
           (DECODE(pol.item_id ,pola.item_id ,NULL,pol.item_id
           ||''-->''
           ||pola.item_id)) item_id,
           (DECODE(pol.job_id , pola.job_id, NULL,pol.job_id
           ||''-->''
           ||pola.job_id)) job_id,
           (DECODE(pol.amount ,pola.amount ,NULL,pol.amount
           ||''-->''
           ||pola.amount)) amount,
           (DECODE(pol.expiration_date , pola.expiration_date , NULL,pol.expiration_date
           ||''-->''
           ||pola.expiration_date)) expiration_date ,
           (DECODE(pol.start_date ,pola.start_date ,NULL,pol.start_date
           ||''-->''
           ||pola.start_date)) start_date ,
           (DECODE(pol.contractor_first_name ,pola.contractor_first_name ,NULL,pol.contractor_first_name
           ||''-->''
           ||pola.contractor_first_name)) contractor_first_name ,
           (DECODE(pol.contractor_last_name ,pola.contractor_last_name ,NULL,pol.contractor_last_name
           ||''-->''
           ||pola.contractor_last_name)) contractor_last_name ,
           (DECODE(pol.item_revision ,pola.item_revision ,NULL,pol.item_revision
           ||''-->''
           ||pola.item_revision)) item_revision ,
           (DECODE(pol.item_description ,pola.item_description ,NULL,pol.item_description
           ||''-->''
           ||pola.item_description)) item_description ,
           (DECODE(pol.unit_meas_lookup_code ,pola.unit_meas_lookup_code , NULL,pol.unit_meas_lookup_code
           ||''-->''
           ||pola.unit_meas_lookup_code)) unit_meas_lookup_code ,
           (DECODE(pol.quantity ,pola.quantity ,NULL,pol.quantity
           ||''-->''
           ||pola.quantity)) quantity ,
           (DECODE(pol.quantity_committed ,pola.quantity_committed ,NULL,pol.quantity_committed
           ||''-->''
           ||pola.quantity_committed)) quantity_committed ,
           (DECODE(pol.committed_amount ,pola.committed_amount ,NULL,pol.committed_amount
           ||''-->''
           ||pola.committed_amount)) committed_amount ,
           (DECODE(pol.unit_price ,pola.unit_price ,NULL,pol.unit_price
           ||''-->''
           ||pola.unit_price)) unit_price ,
           (DECODE(pol.not_to_exceed_price ,pola.not_to_exceed_price , NULL,pol.not_to_exceed_price
           ||''-->''
           ||pola.not_to_exceed_price)) not_to_exceed_price ,
           (DECODE(pol.un_number_id ,pola.un_number_id , NULL,pol.un_number_id
           ||''-->''
           ||pola.un_number_id)) un_number_id ,
           (DECODE(pol.hazard_class_id ,pola.hazard_class_id ,NULL,pol.hazard_class_id
           ||''-->''
           ||pola.hazard_class_id)) hazard_class_id ,
           (DECODE(pol.note_to_vendor , pola.note_to_vendor ,NULL,pol.note_to_vendor
           ||''-->''
           ||pola.note_to_vendor)) note_to_vendor ,
           (DECODE(pol.from_header_id ,pola.from_header_id ,NULL,pol.from_header_id
           ||''-->''
           ||pola.from_header_id)) from_header_id ,
           (DECODE(pol.from_line_id ,pola.from_line_id ,NULL,pol.from_line_id
           ||''-->''
           ||pola.from_line_id)) from_line_id ,
           (DECODE(pol.vendor_product_num ,pola.vendor_product_num ,NULL,pol.vendor_product_num
           ||''-->''
           ||pola.vendor_product_num)) vendor_product_num ,
           (DECODE( pol.contract_id , pola.contract_id ,NULL,pol.contract_id
           ||''-->''
           ||pola.contract_id)) contract_id ,
           (DECODE(pol.price_type_lookup_code ,pola.price_type_lookup_code ,NULL,pol.price_type_lookup_code
           ||''-->''
           ||pola.price_type_lookup_code)) price_type_lookup_code ,
           (DECODE(pol.cancel_flag,pola.cancel_flag,NULL,pol.cancel_flag
           ||''-->''
           ||pola.cancel_flag)) cancel_flag
         FROM PO_LINES_ALL POL,
           PO_LINES_ARCHIVE_ALL POLA,
           PO_HEADERS_ALL POH
         WHERE poh.po_header_id = ##$$FK1$$##
         AND poh.po_header_id                 =pol.po_header_id
         AND poh.type_lookup_code            IN (''STANDARD'',''PLANNED'',''BLANKET'')
         AND NVL(poh.closed_code,''OPEN'') NOT IN (''FINALLY CLOSED'')
         AND NVL(poh.cancel_flag,''N'')        <> ''Y''
         AND POL.po_line_id                   = POLA.po_line_id
         AND POLA.latest_external_flag        = ''Y''
         AND ( (POL.line_num                 <> POLA.line_num)
         OR (POL.item_id                     <> POLA.item_id)
         OR (POL.item_id                     IS NULL
         AND POLA.item_id                    IS NOT NULL)
         OR (POL.item_id                     IS NOT NULL
         AND POLA.item_id                    IS NULL)
         OR (POL.job_id                      <> POLA.job_id)
         OR (POL.job_id                      IS NULL
         AND POLA.job_id                     IS NOT NULL)
         OR (POL.job_id                      IS NOT NULL
         AND POLA.job_id                     IS NULL)
         OR (POL.amount                      <> POLA.amount)
         OR (POL.amount                      IS NULL
         AND POLA.amount                     IS NOT NULL)
         OR (POL.amount                      IS NOT NULL
         AND POLA.amount                     IS NULL)
         OR (POL.expiration_date             IS NULL
         AND POLA.expiration_date            IS NOT NULL)
         OR (POL.expiration_date             IS NOT NULL
         AND POLA.expiration_date            IS NULL)
         OR (TRUNC(POL.expiration_date)      <> TRUNC(POLA.expiration_date))
         OR (POL.start_date                  IS NULL
         AND POLA.start_date                 IS NOT NULL)
         OR (POL.start_date                  IS NOT NULL
         AND POLA.start_date                 IS NULL)
         OR (TRUNC(POL.start_date)           <> TRUNC(POLA.start_date))
         OR (POL.contractor_first_name       <> POLA.contractor_first_name)
         OR (POL.contractor_first_name       IS NULL
         AND POLA.contractor_first_name      IS NOT NULL)
         OR (POL.contractor_first_name       IS NOT NULL
         AND POLA.contractor_first_name      IS NULL)
         OR (POL.contractor_last_name        <> POLA.contractor_last_name)
         OR (POL.contractor_last_name        IS NULL
         AND POLA.contractor_last_name       IS NOT NULL)
         OR (POL.contractor_last_name        IS NOT NULL
         AND POLA.contractor_last_name       IS NULL)
         OR (POL.item_revision               <> POLA.item_revision)
         OR (POL.item_revision               IS NULL
         AND POLA.item_revision              IS NOT NULL)
         OR (POL.item_revision               IS NOT NULL
         AND POLA.item_revision              IS NULL)
         OR (POL.item_description            <> POLA.item_description)
         OR (POL.item_description            IS NULL
         AND POLA.item_description           IS NOT NULL)
         OR (POL.item_description            IS NOT NULL
         AND POLA.item_description           IS NULL)
         OR (POL.unit_meas_lookup_code       <> POLA.unit_meas_lookup_code)
         OR (POL.unit_meas_lookup_code       IS NULL
         AND POLA.unit_meas_lookup_code      IS NOT NULL)
         OR (POL.unit_meas_lookup_code       IS NOT NULL
         AND POLA.unit_meas_lookup_code      IS NULL)
         OR (POL.quantity                    <> POLA.quantity)
         OR (POL.quantity                    IS NULL
         AND POLA.quantity                   IS NOT NULL)
         OR (POL.quantity_committed          <> POLA.quantity_committed)
         OR (POL.quantity_committed          IS NULL
         AND POLA.quantity_committed         IS NOT NULL)
         OR (POL.quantity_committed          IS NOT NULL
         AND POLA.quantity_committed         IS NULL)
         OR (POL.committed_amount            <> POLA.committed_amount)
         OR (POL.committed_amount            IS NULL
         AND POLA.committed_amount           IS NOT NULL)
         OR (POL.committed_amount            IS NOT NULL
         AND POLA.committed_amount           IS NULL)
         OR (POL.unit_price                  <> POLA.unit_price)
         OR (POL.unit_price                  IS NULL
         AND POLA.unit_price                 IS NOT NULL)
         OR (POL.unit_price                  IS NOT NULL
         AND POLA.unit_price                 IS NULL)
         OR (POL.not_to_exceed_price         <> POLA.not_to_exceed_price)
         OR (POL.not_to_exceed_price         IS NULL
         AND POLA.not_to_exceed_price        IS NOT NULL)
         OR (POL.not_to_exceed_price         IS NOT NULL
         AND POLA.not_to_exceed_price        IS NULL)
         OR (POL.un_number_id                <> POLA.un_number_id)
         OR (POL.un_number_id                IS NULL
         AND POLA.un_number_id               IS NOT NULL)
         OR (POL.un_number_id                IS NOT NULL
         AND POLA.un_number_id               IS NULL)
         OR (POL.hazard_class_id             <> POLA.hazard_class_id)
         OR (POL.hazard_class_id             IS NULL
         AND POLA.hazard_class_id            IS NOT NULL)
         OR (POL.hazard_class_id             IS NOT NULL
         AND POLA.hazard_class_id            IS NULL)
         OR (POL.note_to_vendor              <> POLA.note_to_vendor)
         OR (POL.note_to_vendor              IS NULL
         AND POLA.note_to_vendor             IS NOT NULL)
         OR (POL.note_to_vendor              IS NOT NULL
         AND POLA.note_to_vendor             IS NULL)
         OR (POL.note_to_vendor              <> POLA.note_to_vendor)
         OR (POL.note_to_vendor              IS NULL
         AND POLA.note_to_vendor             IS NOT NULL)
         OR (POL.note_to_vendor              IS NOT NULL
         AND POLA.note_to_vendor             IS NULL)
         OR (POL.from_header_id              <> POLA.from_header_id)
         OR (POL.from_header_id              IS NULL
         AND POLA.from_header_id             IS NOT NULL)
         OR (POL.from_header_id              IS NOT NULL
         AND POLA.from_header_id             IS NULL)
         OR (POL.from_line_id                <> POLA.from_line_id)
         OR (POL.from_line_id                IS NULL
         AND POLA.from_line_id               IS NOT NULL)
         OR (POL.from_line_id                IS NOT NULL
         AND POLA.from_line_id               IS NULL)
         OR (POL.vendor_product_num          <> POLA.vendor_product_num)
         OR (POL.vendor_product_num          IS NULL
         AND POLA.vendor_product_num         IS NOT NULL)
         OR (POL.vendor_product_num          IS NOT NULL
         AND POLA.vendor_product_num         IS NULL)
         OR (POL.contract_id                 <> POLA.contract_id)
         OR (POL.contract_id                 IS NULL
         AND POLA.contract_id                IS NOT NULL)
         OR (POL.contract_id                 IS NOT NULL
         AND POLA.contract_id                IS NULL)
         OR (POL.price_type_lookup_code      <> POLA.price_type_lookup_code)
         OR (POL.price_type_lookup_code      IS NULL
         AND POLA.price_type_lookup_code     IS NOT NULL)
         OR (POL.price_type_lookup_code      IS NOT NULL
         AND POLA.price_type_lookup_code     IS NULL)
         OR (POL.cancel_flag                 <> POLA.cancel_flag)
         OR (POL.cancel_flag                 IS NULL
         AND POLA.cancel_flag                IS NOT NULL)
         OR (POL.cancel_flag                 IS NOT NULL
         AND POLA.cancel_flag                IS NULL))
         ORDER BY pol.po_header_id',
   'PO_LINES_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');       


  ---------------------------------
  -- Single Trx Data Integrity PO 3
  ---------------------------------
  add_signature(
   'DATA_SINGLE_PO3',
   'SELECT h.segment1 po_number,
           ll.shipment_type type_lookup_code,
           ll.po_header_id,
           ll.po_header_id "##$$FK1$$##",
           ll.po_line_id,
           ll.line_location_id,
           h.revision_num,
           ll.creation_date,
           ll.last_update_date
    FROM po_line_locations_all ll,
         po_line_locations_archive_all lla,
         po_headers_all h,
         po_headers_archive_all ha,
         po_document_types_all dt
    WHERE h.po_header_id=ll.po_header_id
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status=''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   ll.po_release_id is null
    AND   ll.line_location_id = lla.line_location_id
    AND   lla.latest_external_flag  = ''Y''
    AND   (((ll.quantity <> lla.quantity) OR
            (ll.quantity IS NULL AND lla.quantity IS NOT NULL) OR
            (ll.quantity IS NOT NULL AND lla.quantity IS NULL)) OR
           ((ll.amount <> lla.amount) OR
            (ll.amount IS NULL AND lla.amount IS NOT NULL) OR
            (ll.amount IS NOT NULL AND lla.amount IS NULL)) OR
           ((ll.ship_to_location_id <> lla.ship_to_location_id) OR
            (ll.ship_to_location_id IS NULL AND lla.ship_to_location_id IS NOT NULL) OR
            (ll.ship_to_location_id IS NOT NULL AND lla.ship_to_location_id IS NULL)) OR
           ((ll.need_by_date <> lla.need_by_date) OR
            (ll.need_by_date IS NULL AND lla.need_by_date IS NOT NULL) OR
            (ll.need_by_date IS NOT NULL AND lla.need_by_date IS NULL)) OR
           ((ll.promised_date <> lla.promised_date) OR
            (ll.promised_date IS NULL AND lla.promised_date IS NOT NULL) OR
            (ll.promised_date IS NOT NULL AND lla.promised_date IS NULL)) OR
           ((ll.last_accept_date <> lla.last_accept_date) OR
            (ll.last_accept_date IS NULL AND lla.last_accept_date IS NOT NULL) OR
            (ll.last_accept_date IS NOT NULL AND lla.last_accept_date IS NULL)) OR
           ((ll.price_override <> lla.price_override) OR
            (ll.price_override IS NULL AND lla.price_override IS NOT NULL) OR
            (ll.price_override IS NOT NULL AND lla.price_override IS NULL)) OR
           ((ll.tax_code_id <> lla.tax_code_id) OR
            (ll.tax_code_id IS NULL AND lla.tax_code_id IS NOT NULL) OR
            (ll.tax_code_id IS NOT NULL AND lla.tax_code_id IS NULL)) OR
           ((ll.shipment_num <> lla.shipment_num) OR
            (ll.shipment_num IS NULL AND lla.shipment_num IS NOT NULL) OR
            (ll.shipment_num IS NOT NULL AND lla.shipment_num IS NULL)) OR
           ((ll.sales_order_update_date <> lla.sales_order_update_date) OR
            (ll.sales_order_update_date IS NULL AND
             lla.sales_order_update_date IS NOT NULL) OR
            (ll.sales_order_update_date IS NOT NULL AND
             lla.sales_order_update_date IS NULL)) OR
           ((ll.cancel_flag <> lla.cancel_flag) OR
            (ll.cancel_flag IS NULL AND lla.cancel_flag IS NOT NULL) OR
            (ll.cancel_flag IS NOT NULL AND lla.cancel_flag IS NULL)) OR
           ((ll.start_date <> lla.start_date) OR
            (ll.start_date is null AND lla.start_date is not null) OR
            (ll.start_date is not null AND lla.start_date is null)) OR
           ((ll.end_date <> lla.end_date) OR
            (ll.end_date is null AND lla.end_date is not null) OR
            (ll.end_date is not null AND lla.end_date is null)))
    AND   h.po_header_id = ##$$DOCID$$##',
    'Synchronization Issues with Line Locations Archive',
    'RS',
    'There are data discrepancies between PO_LINES_LOCATIONS_ALL and
     PO_LINE_LOCATIONS_ARCHIVE_ALL for this PO, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_PO3'),
    p_include_in_dx_summary => 'Y');

    l_info.delete;
  ---------------------------------------
  -- Child Single Trx Data Integrity PO 3
  ---------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_PO3',
   'SELECT poh.po_header_id po_header_id ,
           poll.po_line_id,
           poll.line_location_id,
           (DECODE(poll.quantity ,polla.quantity , NULL,poll.quantity
           ||''-->''
           ||polla.quantity)) quantity,
           (DECODE(poll.amount ,polla.amount ,NULL,poll.amount
           ||''-->''
           ||polla.amount)) amount,
           (DECODE(poll.ship_to_location_id ,polla.ship_to_location_id ,NULL,poll.ship_to_location_id
           ||''-->''
           ||polla.ship_to_location_id)) ship_to_location_id ,
           (DECODE(poll.need_by_date ,polla.need_by_date,NULL,poll.need_by_date
           ||''-->''
           ||polla.need_by_date)) need_by_date,
           (DECODE(poll.promised_date ,polla.promised_date ,NULL,poll.promised_date
           ||''-->''
           ||polla.promised_date)) promised_date ,
           (DECODE(poll.last_accept_date ,polla.last_accept_date ,NULL,poll.last_accept_date
           ||''-->''
           ||polla.last_accept_date)) last_accept_date,
           (DECODE(poll.price_override ,polla.price_override ,NULL,poll.price_override
           ||''-->''
           ||polla.price_override)) price_override,
           (DECODE(poll.tax_code_id ,polla.tax_code_id ,NULL,poll.tax_code_id
           ||''-->''
           ||polla.tax_code_id)) tax_code_id ,
           (DECODE(poll.shipment_num ,polla.shipment_num ,NULL,poll.shipment_num
           ||''-->''
           ||polla.shipment_num)) shipment_num,
           (DECODE(poll.sales_order_update_date ,polla.sales_order_update_date ,NULL,poll.sales_order_update_date
           ||''-->''
           ||polla.sales_order_update_date)) sales_order_update_date,
           (DECODE(poll.start_date ,polla.start_date ,NULL,poll.start_date
           ||''-->''
           ||polla.start_date)) start_date,
           (DECODE(poll.end_date ,polla.end_date ,NULL,poll.end_date
           ||''-->''
           ||polla.end_date)) end_date,
           (DECODE(poll.cancel_flag, polla.cancel_flag,NULL,poll.cancel_flag
           ||''-->''
           ||polla.cancel_flag)) cancel_flag
         FROM PO_LINE_LOCATIONS_ALL POLL,
           PO_LINE_LOCATIONS_ARCHIVE_ALL POLLA,
           PO_HEADERS_ALL POH
         WHERE poh.po_header_id = ##$$FK1$$##
         AND poh.po_header_id                 =poll.po_header_id
         AND poh.type_lookup_code            IN (''STANDARD'',''PLANNED'',''BLANKET'')
         AND NVL(poh.closed_code,''OPEN'') NOT IN (''FINALLY CLOSED'')
         AND NVL(poh.cancel_flag,''N'')        <> ''Y''
         AND POLL.po_release_id              IS NULL
         AND POLL.line_location_id            = POLLA.line_location_id
         AND POLLA.latest_external_flag       = ''Y''
         AND ( (POLL.quantity                <> POLLA.quantity)
         OR (POLL.quantity                   IS NULL
         AND POLLA.quantity                  IS NOT NULL)
         OR (POLL.quantity                   IS NOT NULL
         AND POLLA.quantity                  IS NULL)
         OR (POLL.amount                     <> POLLA.amount)
         OR (POLL.amount                     IS NULL
         AND POLLA.amount                    IS NOT NULL)
         OR (POLL.amount                     IS NOT NULL
         AND POLLA.amount                    IS NULL)
         OR (POLL.ship_to_location_id        <> POLLA.ship_to_location_id)
         OR (POLL.ship_to_location_id        IS NULL
         AND POLLA.ship_to_location_id       IS NOT NULL)
         OR (POLL.ship_to_location_id        IS NOT NULL
         AND POLLA.ship_to_location_id       IS NULL)
         OR (POLL.need_by_date               <> POLLA.need_by_date)
         OR (POLL.need_by_date               IS NULL
         AND POLLA.need_by_date              IS NOT NULL)
         OR (POLL.need_by_date               IS NOT NULL
         AND POLLA.need_by_date              IS NULL)
         OR (POLL.promised_date              <> POLLA.promised_date)
         OR (POLL.promised_date              IS NULL
         AND POLLA.promised_date             IS NOT NULL)
         OR (POLL.promised_date              IS NOT NULL
         AND POLLA.promised_date             IS NULL)
         OR (POLL.last_accept_date           <> POLLA.last_accept_date)
         OR (POLL.last_accept_date           IS NULL
         AND POLLA.last_accept_date          IS NOT NULL)
         OR (POLL.last_accept_date           IS NOT NULL
         AND POLLA.last_accept_date          IS NULL)
         OR (POLL.price_override             <> POLLA.price_override)
         OR (POLL.price_override             IS NULL
         AND POLLA.price_override            IS NOT NULL)
         OR (POLL.price_override             IS NOT NULL
         AND POLLA.price_override            IS NULL)
         OR (POLL.tax_code_id                <> POLLA.tax_code_id)
         OR (POLL.tax_code_id                IS NULL
         AND POLLA.tax_code_id               IS NOT NULL)
         OR (POLL.tax_code_id                IS NOT NULL
         AND POLLA.tax_code_id               IS NULL)
         OR (POLL.shipment_num               <> POLLA.shipment_num)
         OR (POLL.shipment_num               IS NULL
         AND POLLA.shipment_num              IS NOT NULL)
         OR (POLL.shipment_num               IS NOT NULL
         AND POLLA.shipment_num              IS NULL)
         OR (POLL.sales_order_update_date    <> POLLA.sales_order_update_date)
         OR (POLL.sales_order_update_date    IS NULL
         AND POLLA.sales_order_update_date   IS NOT NULL)
         OR (POLL.sales_order_update_date    IS NOT NULL
         AND POLLA.sales_order_update_date   IS NULL)
         OR (POLL.start_date                 <> POLLA.start_date)
         OR (POLL.start_date                 IS NULL
         AND POLLA.start_date                IS NOT NULL)
         OR (POLL.start_date                 IS NOT NULL
         AND POLLA.start_date                IS NULL)
         OR (POLL.end_date                   <> POLLA.end_date)
         OR (POLL.end_date                   IS NULL
         AND POLLA.end_date                  IS NOT NULL)
         OR (POLL.end_date                   IS NOT NULL
         AND POLLA.end_date                  IS NULL)
         OR (POLL.cancel_flag                <> POLLA.cancel_flag)
         OR (POLL.cancel_flag                IS NULL
         AND POLLA.cancel_flag               IS NOT NULL)
         OR (POLL.cancel_flag                IS NOT NULL
         AND POLLA.cancel_flag               IS NULL))
         ORDER BY po_header_id DESC',
   'PO_LINE_LOCATIONS_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');       
    
    
  ---------------------------------
  -- Single Trx Data Integrity PO 4
  ---------------------------------
  add_signature(
   'DATA_SINGLE_PO4',
   'SELECT h.segment1 PO_NUMBER,
           h.type_lookup_code type_lookup_code,
           d.po_header_id,
           d.po_header_id "##$$FK1$$##",
           d.po_line_id,
           d.line_location_id,
           d.po_distribution_id,
           h.revision_num,
           d.creation_date,
           d.last_update_date
    FROM po_distributions_all d,
         po_distributions_archive_all da,
         po_headers_all h,
         po_headers_archive_all ha,
         po_document_types_all dt
    WHERE h.po_header_id=d.po_header_id
    AND   d.po_release_id  is NULL
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'')
    AND   h.authorization_status=''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   d.po_distribution_id = da.po_distribution_id
    AND   da.latest_external_flag  = ''Y''
    AND   (((d.quantity_ordered <> da.quantity_ordered) OR
            (d.quantity_ordered IS NULL AND da.quantity_ordered IS NOT NULL) OR
            (d.quantity_ordered IS NOT NULL AND da.quantity_ordered IS NULL)) OR
           ((d.amount_ordered <> da.amount_ordered) OR
            (d.amount_ordered IS NULL AND da.amount_ordered IS NOT NULL) OR
            (d.amount_ordered IS NOT NULL AND da.amount_ordered IS NULL)) OR
           ((d.deliver_to_person_id <> da.deliver_to_person_id) OR
            (d.deliver_to_person_id IS NULL AND da.deliver_to_person_id IS NOT NULL) OR
            (d.deliver_to_person_id IS NOT NULL AND da.deliver_to_person_id IS NULL)) OR
           ((d.recovery_rate <> da.recovery_rate) OR
            (d.recovery_rate IS NULL AND da.recovery_rate IS NOT NULL) OR
            (d.recovery_rate IS NOT NULL AND da.recovery_rate IS NULL)))
    AND   h.po_header_id = ##$$DOCID$$##',
    'Synchronization Issues with Distributions Archive',
    'RS',
    'There are data discrepancies between PO_DISTRIBUTIONS_ALL and
     PO_DISTRIBUTIONS_ARCHIVE_ALL for this PO, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_PO4'),
    p_include_in_dx_summary => 'Y');

    l_info.delete;
  ---------------------------------------
  -- Child Single Trx Data Integrity PO 4
  ---------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_PO4',
   'SELECT poh.po_header_id,
      pod.po_line_id,
      pod.line_location_id,
      pod.po_distribution_id,
      (DECODE(POD.quantity_ordered ,PODA.quantity_ordered ,NULL,POD.quantity_ordered
      ||''-->''
      ||PODA.quantity_ordered)) quantity,
      (DECODE(POD.amount_ordered ,PODA.amount_ordered ,NULL,POD.amount_ordered
      ||''-->''
      ||PODA.amount_ordered)) amount_ordered ,
      (DECODE(POD.deliver_to_person_id,PODA.deliver_to_person_id,NULL,POD.deliver_to_person_id
      ||''-->''
      ||PODA.deliver_to_person_id)) deliver_to_person_id,
      (DECODE(POD.recovery_rate ,PODA.recovery_rate ,NULL,POD.recovery_rate
      ||''-->''
      ||PODA.recovery_rate)) recovery_rate
    FROM PO_DISTRIBUTIONS_ALL POD,
      PO_DISTRIBUTIONS_ARCHIVE_ALL PODA,
      PO_HEADERS_ALL POH
    WHERE poh.po_header_id = ##$$FK1$$##
      AND poh.po_header_id                = pod.po_header_id
      AND pod.po_release_id               IS NULL
      AND poh.type_lookup_code            IN (''STANDARD'',''PLANNED'')
      AND NVL(poh.closed_code,''OPEN'') NOT IN (''FINALLY CLOSED'')
      AND NVL(poh.cancel_flag,''N'')        <> ''Y''
      AND POD.po_distribution_id           = PODA.po_distribution_id
      AND PODA.latest_external_flag        = ''Y''
      AND ( (POD.quantity_ordered         <> PODA.quantity_ordered)
      OR (POD.quantity_ordered            IS NULL
      AND PODA.quantity_ordered           IS NOT NULL)
      OR (POD.quantity_ordered            IS NOT NULL
      AND PODA.quantity_ordered           IS NULL)
      OR (POD.amount_ordered              <> PODA.amount_ordered)
      OR (POD.amount_ordered              IS NULL
      AND PODA.amount_ordered             IS NOT NULL)
      OR (POD.amount_ordered              IS NOT NULL
      AND PODA.amount_ordered             IS NULL)
      OR (POD.deliver_to_person_id        <> PODA.deliver_to_person_id)
      OR (POD.deliver_to_person_id        IS NULL
      AND PODA.deliver_to_person_id       IS NOT NULL)
      OR (POD.deliver_to_person_id        IS NOT NULL
      AND PODA.deliver_to_person_id       IS NULL)
      OR (POD.recovery_rate               <> PODA.recovery_rate)
      OR (POD.recovery_rate               IS NULL
      AND PODA.recovery_rate              IS NOT NULL)
      OR (POD.recovery_rate               IS NOT NULL
      AND PODA.recovery_rate              IS NULL))
    ORDER BY po_header_id DESC',
   'PO_DISTRIBUTIONS_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');   
    
    
  ----------------------------------
  -- Single Trx Data Integrity  PO 5
  ----------------------------------
  l_info.delete;
  l_info('Doc ID') := '465068.1';
  add_signature(
   'DATA_SINGLE_PO5',
   'SELECT h.org_id,
           h.po_header_id,
           h.segment1 PO_NUMBER,
           ''Purchase Order'',
           pol.po_line_id,
           pol.line_num
    FROM po_headers_all h,
         po_lines_all pol
    WHERE h.po_header_id = pol.po_header_id
    AND   h.po_header_id = ##$$DOCID$$##
    AND   EXISTS (
              SELECT ll.po_line_id
              FROM po_line_locations_all ll,
                   po_system_parameters_all sp
              WHERE ll.po_line_id = pol.po_line_id
              AND   ll.shipment_type in (''STANDARD'',''BLANKET'')
              AND   ll.po_release_id is null
              AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                     (1 - nvl(ll.receive_close_tolerance,
                      nvl(sp.receive_close_tolerance,0))/100)) -
                    decode(sp.receive_close_code,
                      ''ACCEPTED'', nvl(ll.quantity_accepted,0),
                      ''DELIVERED'', (
                         SELECT sum(nvl(d1.quantity_delivered,0))
                         FROM po_distributions_all d1
                         WHERE d1.line_location_id= ll.line_location_id),
                      nvl(ll.quantity_received,0)) <= 0.000000000000001
              AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                     (1 - nvl(ll.invoice_close_tolerance,
                            nvl(sp.invoice_close_tolerance,0))/100 )) -
                    nvl(ll.quantity_billed,0) <= 0.000000000000001
              AND   nvl(ll.closed_code,''OPEN'') IN (
                      ''OPEN'',''CLOSED FOR RECEIVING'',''CLOSED FOR INVOICE''))
    ORDER BY h.org_id, h.po_header_id, pol.po_line_id',
    'Shipments Eligible to be Closed',
    'RS',
    'This purchase order has shipments which are not closed but which are
     fully received and billed.',
    'Follow the solution instructions provided in [465068.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  ----------------------------------
  -- Single Trx Data Integrity REL 1
  ----------------------------------
  add_signature(
   'DATA_SINGLE_REL1',
   'SELECT r.po_release_id,
           r.release_num,
           r.release_date,
           r.po_header_id,
           r.shipping_control,
           r.acceptance_required_flag ,
           r.acceptance_due_date,
           to_char(r.creation_date,
             ''DD-MON-RRRR HH24:MI:SS'') creation_date,
           to_char(r.last_update_date,
             ''DD-MON-RRRR HH24:MI:SS'') last_update_date
    FROM po_releases_all r,
         po_releases_archive_all ra,
         po_acceptances a,
         po_document_types_all dt
    WHERE r.po_release_id = ra.po_release_id
    AND   r.authorization_status = ''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type = dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num = ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   r.po_release_id = a.po_release_id(+)
    AND   a.revision_num (+) = r.revision_num
    AND   a.accepted_flag(+) = ''Y''
    AND   ra.latest_external_flag = ''Y''
    AND   ((r.release_num <> ra.release_num) OR
           (r.release_date <> ra.release_date) OR
           ((r.shipping_control <> ra.shipping_control) OR
            (r.shipping_control IS NULL AND ra.shipping_control IS NOT NULL) OR
            (r.shipping_control IS NOT NULL AND ra.shipping_control IS NULL)) OR
           (((r.acceptance_required_flag <> ra.acceptance_required_flag) AND NOT
             (nvl(r.acceptance_required_flag,''X'') = ''N'' AND
              nvl(ra.acceptance_required_flag,''X'') = ''Y'' AND
              nvl(a.accepted_flag,''X'') = ''Y'')) OR
            (r.acceptance_required_flag = ''Y'' AND
             ra.acceptance_required_flag = ''Y'' AND
             nvl(a.accepted_flag,''X'') = ''Y'') OR
            (r.acceptance_required_flag IS NULL AND
             ra.acceptance_required_flag IS NOT NULL) OR
            (r.acceptance_required_flag IS NOT NULL AND
             ra.acceptance_required_flag IS NULL)) OR
           ((r.acceptance_due_date <> ra.acceptance_due_date) OR
            (r.acceptance_due_date IS NULL AND
             ra.acceptance_due_date IS NOT NULL
             AND nvl(a.accepted_flag,''N'') = ''N'') OR
            (r.acceptance_due_date IS NOT NULL AND
             ra.acceptance_due_date IS NULL)))
    AND   r.po_release_id = ##$$RELID$$##',
    'Synchronization Issues with Releases Archive',
    'RS',
    'There are data discrepancies between PO_RELEASES_ALL and
     PO_RELEASES_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_REL1'),
    p_include_in_dx_summary => 'Y');

    l_info.delete;

  ----------------------------------------
  -- Child Single Trx Data Integrity REL 1
  ----------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_REL1',
   'SELECT por.po_header_id,
           por.po_release_id,
           por.release_num,
           (DECODE(por.release_num,pora.release_num,NULL,por.release_num
           ||''-->''
           ||pora.release_num)) release_num,
           (DECODE(por.Agent_id,pora.Agent_id,NULL,por.Agent_id
           ||''-->''
           ||pora.Agent_id)) Agent_id,
           (DECODE(por.release_date,pora.release_date,NULL,por.release_date
           ||''-->''
           ||pora.release_date)) release_date,
           (DECODE(por.shipping_control,pora.shipping_control,NULL,por.shipping_control
           ||''-->''
           ||pora.shipping_control)) shipping_control,
           (DECODE(por.acceptance_required_flag ,pora.acceptance_required_flag ,NULL,por.acceptance_required_flag
           ||''-->''
           ||pora.acceptance_required_flag)) acceptance_required_flag ,
           (DECODE(por.acceptance_due_date ,pora.acceptance_due_date ,NULL,por.acceptance_due_date
           ||''-->''
           ||pora.acceptance_due_date)) acceptance_due_date
         FROM PO_RELEASES_ALL POR,
           PO_RELEASES_ARCHIVE_ALL PORA,
           po_acceptances pa
         WHERE por.po_header_id = ##$$FK1$$##
               AND POR.po_release_id                          = PORA.po_release_id
               AND NVL(por.closed_code,''OPEN'') NOT           IN (''FINALLY CLOSED'')
               AND NVL(por.cancel_flag,''N'')                  <> ''Y''
               AND por.po_release_id                          =pa.po_release_id(+)
               AND pa.revision_num (+)                        = por.revision_num
               AND pa.accepted_flag(+)                        =''Y''
               AND PORA.latest_external_flag                  = ''Y''
               AND ( (POR.release_num                        <> PORA.release_num)
               OR (POR.agent_id                              <> PORA.agent_id)
               OR (POR.release_date                          <> PORA.release_date)
               OR (POR.shipping_control                      <> PORA.shipping_control)
               OR (POR.shipping_control                      IS NULL
               AND PORA.shipping_control                     IS NOT NULL)
               OR (POR.shipping_control                      IS NOT NULL
               AND PORA.shipping_control                     IS NULL)
               OR ((POR.acceptance_required_flag             <> PORA.acceptance_required_flag)
               AND NOT (NVL(POR.acceptance_required_flag,''X'') =''N''
               AND NVL(PORA.acceptance_required_flag,''X'')     = ''Y''
               AND NVL(pa.accepted_flag,''X'')                  =''Y''))
               OR (POR.acceptance_required_flag               = ''Y''
               AND PORA.acceptance_required_flag              =''Y''
               AND NVL(pa.accepted_flag,''X'')                  =''Y'')
               OR (POR.acceptance_required_flag              IS NULL
               AND PORA.acceptance_required_flag             IS NOT NULL)
               OR (POR.acceptance_required_flag              IS NOT NULL
               AND PORA.acceptance_required_flag             IS NULL)
               OR (POR.acceptance_due_date                   <> PORA.acceptance_due_date)
               OR (POR.acceptance_due_date                   IS NULL
               AND PORA.acceptance_due_date                  IS NOT NULL
               AND NVL(pa.accepted_flag,''N'')                  =''N'')
               OR (POR.acceptance_due_date                   IS NOT NULL
               AND PORA.acceptance_due_date                  IS NULL))
         ORDER BY POR.po_header_id',
   'PO_RELEASES_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');   
        
    
  ----------------------------------
  -- Single Trx Data Integrity REL 2
  ----------------------------------
  add_signature(
   'DATA_SINGLE_REL2',
   'SELECT r.po_release_id,
           r.release_type type_lookup_code,
           ll.po_header_id,
           ll.po_line_id,
           ll.line_location_id,
           r.revision_num,
           ll.creation_date,
           ll.last_update_date
    FROM po_line_locations_all ll,
         po_line_locations_archive_all lla,
         po_releases_all r,
         po_releases_archive_all ra  ,
         po_document_types_all dt
    WHERE r.po_release_id=ll.po_release_id
    AND   r.po_release_id = ra.po_release_id
    AND   ra.latest_external_flag = ''Y''
    AND   r.authorization_status=''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type = dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num = ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   ll.line_location_id = lla.line_location_id
    AND   lla.latest_external_flag  = ''Y''
    AND   (((ll.quantity <> lla.quantity) OR
            (ll.quantity IS NULL AND lla.quantity IS NOT NULL) OR
            (ll.quantity IS NOT NULL AND lla.quantity IS NULL)) OR
           ((ll.amount <> lla.amount) OR
            (ll.amount IS NULL AND lla.amount IS NOT NULL) OR
            (ll.amount IS NOT NULL AND lla.amount IS NULL)) OR
           ((ll.ship_to_location_id <> lla.ship_to_location_id) OR
            (ll.ship_to_location_id IS NULL AND lla.ship_to_location_id IS NOT NULL) OR
            (ll.ship_to_location_id IS NOT NULL AND lla.ship_to_location_id IS NULL)) OR
           ((ll.need_by_date <> lla.need_by_date) OR
            (ll.need_by_date IS NULL AND lla.need_by_date IS NOT NULL) OR
            (ll.need_by_date IS NOT NULL AND lla.need_by_date IS NULL)) OR
           ((ll.promised_date <> lla.promised_date) OR
            (ll.promised_date IS NULL AND lla.promised_date IS NOT NULL) OR
            (ll.promised_date IS NOT NULL AND lla.promised_date IS NULL)) OR
           ((ll.last_accept_date <> lla.last_accept_date) OR
            (ll.last_accept_date IS NULL AND lla.last_accept_date IS NOT NULL) OR
            (ll.last_accept_date IS NOT NULL AND lla.last_accept_date IS NULL)) OR
           ((ll.price_override <> lla.price_override) OR
            (ll.price_override IS NULL AND lla.price_override IS NOT NULL) OR
            (ll.price_override IS NOT NULL AND lla.price_override IS NULL)) OR
           ((ll.tax_code_id <> lla.tax_code_id) OR
            (ll.tax_code_id IS NULL AND lla.tax_code_id IS NOT NULL) OR
            (ll.tax_code_id IS NOT NULL AND lla.tax_code_id IS NULL)) OR
           ((ll.shipment_num <> lla.shipment_num) OR
            (ll.shipment_num IS NULL AND lla.shipment_num IS NOT NULL) OR
            (ll.shipment_num IS NOT NULL AND lla.shipment_num IS NULL)) OR
           ((ll.sales_order_update_date <> lla.sales_order_update_date) OR
            (ll.sales_order_update_date IS NULL AND
             lla.sales_order_update_date IS NOT NULL) OR
            (ll.sales_order_update_date IS NOT NULL AND
             lla.sales_order_update_date IS NULL)) OR
           ((ll.cancel_flag <> lla.cancel_flag) OR
            (ll.cancel_flag IS NULL AND lla.cancel_flag IS NOT NULL) OR
            (ll.cancel_flag IS NOT NULL AND lla.cancel_flag IS NULL)) OR
           ((ll.start_date <> lla.start_date) OR
            (ll.start_date is null AND lla.start_date is not null) OR
            (ll.start_date is not null AND lla.start_date is null)) OR
           ((ll.end_date <> lla.end_date) OR
            (ll.end_date is null AND lla.end_date is not null) OR
            (ll.end_date is not null AND lla.end_date is null)))
    AND   r.po_release_id = ##$$RELID$$##',
    'Synchronization Issues with Line Locations Archive',
    'RS',
    'There are data discrepancies between PO_LINE_LOCATIONS_ALL and
     PO_LINE_LOCATIONS_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_REL2'),
    p_include_in_dx_summary => 'Y');

    l_info.delete;

  ----------------------------------------
  -- Child Single Trx Data Integrity REL 2
  ----------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_REL2',
   'SELECT poll.po_header_id po_header_id,
           por.release_id,
           poll.po_line_id,
           poll.line_location_id,
           (DECODE(poll.quantity ,polla.quantity , NULL,poll.quantity
           ||''-->''
           ||polla.quantity)) quantity,
           (DECODE(poll.amount ,polla.amount ,NULL,poll.amount
           ||''-->''
           ||polla.amount)) amount,
           (DECODE(poll.ship_to_location_id ,polla.ship_to_location_id ,NULL,poll.ship_to_location_id
           ||''-->''
           ||polla.ship_to_location_id)) ship_to_location_id ,
           (DECODE(poll.need_by_date ,polla.need_by_date,NULL,poll.need_by_date
           ||''-->''
           ||polla.need_by_date)) need_by_date,
           (DECODE(poll.promised_date ,polla.promised_date ,NULL,poll.promised_date
           ||''-->''
           ||polla.promised_date)) promised_date ,
           (DECODE(poll.last_accept_date ,polla.last_accept_date ,NULL,poll.last_accept_date
           ||''-->''
           ||polla.last_accept_date)) last_accept_date,
           (DECODE(poll.price_override ,polla.price_override ,NULL,poll.price_override
           ||''-->''
           ||polla.price_override)) price_override,
           (DECODE(poll.tax_code_id ,polla.tax_code_id ,NULL,poll.tax_code_id
           ||''-->''
           ||polla.tax_code_id)) tax_code_id ,
           (DECODE(poll.shipment_num ,polla.shipment_num ,NULL,poll.shipment_num
           ||''-->''
           ||polla.shipment_num)) shipment_num,
           (DECODE(poll.sales_order_update_date ,polla.sales_order_update_date ,NULL,poll.sales_order_update_date
           ||''-->''
           ||polla.sales_order_update_date)) sales_order_update_date,
           (DECODE(poll.start_date ,polla.start_date ,NULL,poll.start_date
           ||''-->''
           ||polla.start_date)) start_date,
           (DECODE(poll.end_date ,polla.end_date ,NULL,poll.end_date
           ||''-->''
           ||polla.end_date)) end_date,
           (DECODE(poll.cancel_flag, polla.cancel_flag,NULL,poll.cancel_flag
           ||''-->''
           ||polla.cancel_flag)) cancel_flag
         FROM PO_LINE_LOCATIONS_ALL POLL,
           PO_LINE_LOCATIONS_ARCHIVE_ALL POLLA,
           PO_RELEASES_ALL POR
         WHERE por.po_release_id = ##$$FK1$$##
         AND por.po_release_id                =poll.po_release_id
         AND por.release_type                 = ''BLANKET''
         AND NVL(por.closed_code,''OPEN'') NOT IN (''FINALLY CLOSED'')
         AND NVL(por.cancel_flag,''N'')        <> ''Y''
         AND POLL.line_location_id            = POLLA.line_location_id
         AND POLLA.latest_external_flag       = ''Y''
         AND ( (POLL.quantity                <> POLLA.quantity)
         OR (POLL.quantity                   IS NULL
         AND POLLA.quantity                  IS NOT NULL)
         OR (POLL.quantity                   IS NOT NULL
         AND POLLA.quantity                  IS NULL)
         OR (POLL.amount                     <> POLLA.amount)
         OR (POLL.amount                     IS NULL
         AND POLLA.amount                    IS NOT NULL)
         OR (POLL.amount                     IS NOT NULL
         AND POLLA.amount                    IS NULL)
         OR (POLL.ship_to_location_id        <> POLLA.ship_to_location_id)
         OR (POLL.ship_to_location_id        IS NULL
         AND POLLA.ship_to_location_id       IS NOT NULL)
         OR (POLL.ship_to_location_id        IS NOT NULL
         AND POLLA.ship_to_location_id       IS NULL)
         OR (POLL.need_by_date               <> POLLA.need_by_date)
         OR (POLL.need_by_date               IS NULL
         AND POLLA.need_by_date              IS NOT NULL)
         OR (POLL.need_by_date               IS NOT NULL
         AND POLLA.need_by_date              IS NULL)
         OR (POLL.promised_date              <> POLLA.promised_date)
         OR (POLL.promised_date              IS NULL
         AND POLLA.promised_date             IS NOT NULL)
         OR (POLL.promised_date              IS NOT NULL
         AND POLLA.promised_date             IS NULL)
         OR (POLL.last_accept_date           <> POLLA.last_accept_date)
         OR (POLL.last_accept_date           IS NULL
         AND POLLA.last_accept_date          IS NOT NULL)
         OR (POLL.last_accept_date           IS NOT NULL
         AND POLLA.last_accept_date          IS NULL)
         OR (POLL.price_override             <> POLLA.price_override)
         OR (POLL.price_override             IS NULL
         AND POLLA.price_override            IS NOT NULL)
         OR (POLL.price_override             IS NOT NULL
         AND POLLA.price_override            IS NULL)
         OR (POLL.tax_code_id                <> POLLA.tax_code_id)
         OR (POLL.tax_code_id                IS NULL
         AND POLLA.tax_code_id               IS NOT NULL)
         OR (POLL.tax_code_id                IS NOT NULL
         AND POLLA.tax_code_id               IS NULL)
         OR (POLL.shipment_num               <> POLLA.shipment_num)
         OR (POLL.shipment_num               IS NULL
         AND POLLA.shipment_num              IS NOT NULL)
         OR (POLL.shipment_num               IS NOT NULL
         AND POLLA.shipment_num              IS NULL)
         OR (POLL.sales_order_update_date    <> POLLA.sales_order_update_date)
         OR (POLL.sales_order_update_date    IS NULL
         AND POLLA.sales_order_update_date   IS NOT NULL)
         OR (POLL.sales_order_update_date    IS NOT NULL
         AND POLLA.sales_order_update_date   IS NULL)
         OR (POLL.start_date                 <> POLLA.start_date)
         OR (POLL.start_date                 IS NULL
         AND POLLA.start_date                IS NOT NULL)
         OR (POLL.start_date                 IS NOT NULL
         AND POLLA.start_date                IS NULL)
         OR (POLL.end_date                   <> POLLA.end_date)
         OR (POLL.end_date                   IS NULL
         AND POLLA.end_date                  IS NOT NULL)
         OR (POLL.end_date                   IS NOT NULL
         AND POLLA.end_date                  IS NULL)
         OR (POLL.cancel_flag                <> POLLA.cancel_flag)
         OR (POLL.cancel_flag                IS NULL
         AND POLLA.cancel_flag               IS NOT NULL)
         OR (POLL.cancel_flag                IS NOT NULL
         AND POLLA.cancel_flag               IS NULL))
         ORDER BY po_header_id DESC',
   'PO_LINE_LOCATIONS_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');   
   
  ----------------------------------
  -- Single Trx Data Integrity REL 3
  ----------------------------------
  add_signature(
   'DATA_SINGLE_REL3',
   'SELECT r.po_release_id,
           r.po_release_id "##$$FK1$$##", 
           r.release_type type_lookup_code,
           d.po_header_id,
           d.po_line_id,
           d.line_location_id,
           d.po_distribution_id,
           r.revision_num,
           d.creation_date,
           d.last_update_date
    FROM po_distributions_all d,
         po_distributions_archive_all da,
         po_releases_all r,
         po_releases_archive_all ra,
         po_document_types_all dt
    WHERE r.po_release_id=d.po_release_id
    AND   r.po_header_id = ra.po_header_id
    AND   ra.latest_external_flag = ''Y''
    AND   r.authorization_status=''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type=dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num=ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   d.po_distribution_id = da.po_distribution_id
    AND   da.latest_external_flag  = ''Y''
    AND   (((d.quantity_ordered <> da.quantity_ordered) OR
            (d.quantity_ordered IS NULL AND da.quantity_ordered IS NOT NULL) OR
            (d.quantity_ordered IS NOT NULL AND da.quantity_ordered IS NULL)) OR
           ((d.amount_ordered <> da.amount_ordered) OR
            (d.amount_ordered IS NULL AND da.amount_ordered IS NOT NULL) OR
            (d.amount_ordered IS NOT NULL AND da.amount_ordered IS NULL)) OR
           ((d.deliver_to_person_id <> da.deliver_to_person_id) OR
            (d.deliver_to_person_id IS NULL AND
             da.deliver_to_person_id IS NOT NULL) OR
            (d.deliver_to_person_id IS NOT NULL AND
             da.deliver_to_person_id IS NULL)) OR
           ((d.recovery_rate <> da.recovery_rate) OR
            (d.recovery_rate IS NULL AND da.recovery_rate IS NOT NULL) OR
            (d.recovery_rate IS NOT NULL AND da.recovery_rate IS NULL)))
    AND   r.po_release_id = ##$$RELID$$##',
    'Synchronization Issues with Distributions Archive',
    'RS',
    'There are data discrepancies between PO_DISTRIBUTIONS_ALL and
     PO_DISTRIBUTIONS_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('CHILD_DATA_SINGLE_REL3'),
    p_include_in_dx_summary => 'Y');
    
    l_info.delete;
  ----------------------------------------
  -- Child Single Trx Data Integrity REL 3
  ----------------------------------------

   add_signature(
   'CHILD_DATA_SINGLE_REL3',
   'SELECT pod.po_header_id,
      por.release_id,
      pod.po_line_id,
      pod.line_location_id,
      pod.po_distribution_id,
      (DECODE(POD.quantity_ordered ,PODA.quantity_ordered ,NULL,POD.quantity_ordered
      ||''-->''
      ||PODA.quantity_ordered)) quantity,
      (DECODE(POD.amount_ordered ,PODA.amount_ordered ,NULL,POD.amount_ordered
      ||''-->''
      ||PODA.amount_ordered)) amount_ordered ,
      (DECODE(POD.deliver_to_person_id,PODA.deliver_to_person_id,NULL,POD.deliver_to_person_id
      ||''-->''
      ||PODA.deliver_to_person_id)) deliver_to_person_id,
      (DECODE(POD.recovery_rate ,PODA.recovery_rate ,NULL,POD.recovery_rate
      ||''-->''
      ||PODA.recovery_rate)) recovery_rate
    FROM PO_DISTRIBUTIONS_ALL POD,
      PO_DISTRIBUTIONS_ARCHIVE_ALL PODA,
      PO_RELEASES_ALL POR
    WHERE por.po_release_id               = ##$$FK1$$##
    AND por.po_release_id                =pod.po_release_id
    AND por.release_type                IN (''BLANKET'')
    AND NVL(por.closed_code,''OPEN'') NOT IN (''FINALLY CLOSED'')
    AND NVL(por.cancel_flag,''N'')        <> ''Y''
    AND POD.po_distribution_id           = PODA.po_distribution_id
    AND PODA.latest_external_flag        = ''Y''
    AND ( (POD.quantity_ordered         <> PODA.quantity_ordered)
    OR (POD.quantity_ordered            IS NULL
    AND PODA.quantity_ordered           IS NOT NULL)
    OR (POD.quantity_ordered            IS NOT NULL
    AND PODA.quantity_ordered           IS NULL)
    OR (POD.amount_ordered              <> PODA.amount_ordered)
    OR (POD.amount_ordered              IS NULL
    AND PODA.amount_ordered             IS NOT NULL)
    OR (POD.amount_ordered              IS NOT NULL
    AND PODA.amount_ordered             IS NULL)
    OR (POD.deliver_to_person_id        <> PODA.deliver_to_person_id)
    OR (POD.deliver_to_person_id        IS NULL
    AND PODA.deliver_to_person_id       IS NOT NULL)
    OR (POD.deliver_to_person_id        IS NOT NULL
    AND PODA.deliver_to_person_id       IS NULL)
    OR (POD.recovery_rate               <> PODA.recovery_rate)
    OR (POD.recovery_rate               IS NULL
    AND PODA.recovery_rate              IS NOT NULL)
    OR (POD.recovery_rate               IS NOT NULL
    AND PODA.recovery_rate              IS NULL))
    ORDER BY po_header_id DESC',
   'PO_DISTRIBUTIONS_ALL - differences between the archive and the main table',
   'RS',
   'The above differences have been found between the main table record and the corresponding archive record',
   'The above columns are either null or have a value like "A --> B" where A is the value in the main table while B is the value in the archive table:
    <ul>
      <li>A null in any column means there is no change and no action is required as the two values are the same
      <li>A value like A-->B would mean that the value in the specified column has to be changes from A to B using the application forms
      <li>A column value like -->B would mean that the null in the specified column has to be changed to B.
      <li>Finally, a value like  A--> would mean that the A in the specified column has to be changed to null.
   </ul>',
   null,
   'FAILURE',
   'W',
   'RS');   
        

  ----------------------------------
  -- Single Trx Data Integrity REL 4
  ----------------------------------
  l_info.delete;
  l_info('Doc ID') := '465068.1';
  add_signature(
   'DATA_SINGLE_REL4',
   'SELECT h.org_id,
           h.po_header_id,
           h.segment1 po_number,
           ''Blanket Release'',
           r.release_num,
           r.po_release_id
    FROM po_releases_all r,
         po_headers_all h
    WHERE r.po_release_id = ##$$RELID$$##
    AND   r.po_header_id = h.po_header_id
    AND   EXISTS (
            SELECT ll.po_release_id
            FROM po_line_locations_all ll,
                 po_system_parameters_all sp
            WHERE ll.po_release_id = r.po_release_id
            AND   ll.shipment_type in (''STANDARD'',''BLANKET'')
            AND   ll.po_release_id is not null
            AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                   (1 - nvl(ll.receive_close_tolerance,
                      nvl(sp.receive_close_tolerance,0))/100)) -
                   decode(sp.receive_close_code,
                     ''ACCEPTED'', nvl(ll.quantity_accepted,0),
                     ''DELIVERED'', (
                        SELECT sum(nvl(POD1.quantity_delivered,0))
                        FROM po_distributions_all pod1
                        WHERE pod1.line_location_id= ll.line_location_id),
                     nvl(ll.quantity_received,0)) <= 0.000000000000001
            AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                   (1 - nvl(ll.invoice_close_tolerance,
                      nvl(sp.invoice_close_tolerance,0))/100)) -
                   nvl(ll.quantity_billed,0) <= 0.000000000000001
            AND   nvl(ll.closed_code,''OPEN'') IN (
                    ''OPEN'',''CLOSED FOR RECEIVING'',''CLOSED FOR INVOICE''))
    ORDER BY h.org_id, h.po_header_id, h.segment1, r.release_num',
    'Shipments Eligible to be Closed',
    'RS',
    'This blanket release has shipments which are not closed but which are
     fully received and billed.',
    'Follow the solution instructions provided in [465068.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 1
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '427917.1';
  l_info('Script Name') := 'poarsynf.sql';
  add_signature(
   'DATA_SINGLE_POREL1',
   'SELECT poh.segment1,
           poll.po_header_id,
           poll.po_line_id,
           poll.line_location_id,
           poll.po_release_id,
           pol.order_type_lookup_code,
           nvl(poll.quantity_billed,0) qtyamt_billed_on_po_line_loc,
           sum(nvl(pod.quantity_billed,0)) qtyamt_billed_on_po_dist
    FROM po_line_locations_all poll,
         po_distributions_all pod,
         po_lines_all pol,
         po_headers_all poh
    WHERE poll.line_location_id=pod.line_location_id
    AND   pol.po_line_id= pod.po_line_id
    AND   pol.po_header_id = poh.po_header_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''AMOUNT'',''QUANTITY'')
    AND   nvl(poll.cancel_flag,''N'') <> ''Y''
    AND   nvl(poll.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   poll.shipment_type IN (''STANDARD'',''BLANKET'',''PLANNED'',''SCHEDULED'')
    AND   poh.po_header_id = ##$$DOCID$$##
    GROUP BY poh.segment1, poll.po_header_id, poll.po_line_id,
             poll.line_location_id, poll.po_release_id,
             pol.order_type_lookup_code, nvl(poll.quantity_billed,0)
    HAVING   round(nvl(poll.quantity_billed,0),15) <>
               round(sum(nvl(pod.quantity_billed,0)),15)
    UNION ALL
    SELECT poh.segment1,
           poll.po_header_id,
           poll.po_line_id,
           poll.line_location_id,
           poll.po_release_id,
           pol.order_type_lookup_code,
           nvl(poll.amount_billed,0) qtyamt_billed_on_po_line_loc,
           sum(nvl(pod.amount_billed,0)) qtyamt_billed_on_po_dist
    FROM po_line_locations_all poll,
         po_distributions_all pod,
         po_lines_all pol,
         po_headers_all poh
    WHERE poll.line_location_id=pod.line_location_id
    AND   pol.po_line_id= pod.po_line_id
    AND   pol.po_header_id = poh.po_header_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''FIXED PRICE'',''RATE'')
    AND   nvl(poll.cancel_flag,''N'') <> ''Y''
    AND   nvl(poll.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   poll.shipment_type in (''STANDARD'',''BLANKET'',''PLANNED'',''SCHEDULED'')
    AND   poh.po_header_id = ##$$DOCID$$##
    GROUP BY poh.segment1, poll.po_header_id, poll.po_line_id,
             poll.line_location_id, poll.po_release_id,
             pol.order_type_lookup_code, nvl(poll.amount_billed,0)
    HAVING  round(nvl(poll.amount_billed,0),15) <>
              round(sum(nvl(pod.amount_billed,0)),15)',
    'Mismatched Quantity Billed',
    'RS',
    'This document has a mismatch in the quantity billed between the shipments
     and the distributions.',
    'Follow the solution instructions provided in [427917.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 2
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '454060.1';
  add_signature(
   'DATA_SINGLE_POREL2',
   'SELECT poh.segment1,
           pod.po_header_id,
           pod.po_line_id,
           pod.line_location_id,
           pod.po_release_id,
           pod.po_distribution_id,
           nvl(pod.quantity_billed,0) qtybilled_on_po_dist,
           nvl(pod.amount_billed,0) amtbilled_on_po_dist,
           sum(nvl(aid.quantity_invoiced,0)) qtyinvoiced_on_ap_dist,
           sum(nvl(aid.amount,0)) amtinvoiced_on_ap_dist,
           pol.order_type_lookup_code
    FROM po_distributions_all pod,
         ap_invoice_distributions_all aid,
         po_lines_all pol,
         po_headers_all poh
    WHERE pod.po_distribution_id=aid.po_distribution_id
    AND   pod.po_line_id = pol.po_line_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''AMOUNT'',''QUANTITY'')
    AND   aid.line_type_lookup_code in (''ITEM'',''PREPAY'',''ACCRUAL'')
    AND   poh.po_header_id = pol.po_header_id
    AND   poh.po_header_id = ##$$DOCID$$##
    GROUP BY poh.segment1, pod.po_header_id, pod.po_line_id,
             pod.line_location_id, pod.po_release_id,
             pod.po_distribution_id, nvl(pod.quantity_billed,0),
             nvl(pod.amount_billed,0), pol.order_type_lookup_code
    HAVING (round(nvl(pod.quantity_billed,0),15) <>
             round(sum(nvl(aid.quantity_invoiced,0)),15) OR
            round(nvl(pod.amount_billed,0),15) <>
              round(sum(nvl(aid.amount,0)),15))
    UNION ALL
    SELECT poh.segment1,
           pod.po_header_id,
           pod.po_line_id,
           pod.line_location_id,
           pod.po_release_id,
           pod.po_distribution_id,
           nvl(pod.quantity_billed,0) qtybilled_on_po_dist,
           nvl(pod.amount_billed,0) amtbilled_on_po_dist,
           sum(nvl(aid.quantity_invoiced,0)) qtyinvoiced_on_ap_dist,
           sum(nvl(aid.amount,0)) amtinvoiced_on_ap_dist,
           pol.order_type_lookup_code
    FROM po_distributions_all pod,
    ap_invoice_distributions_all aid,
    po_lines_all pol,
    po_headers_all poh
    WHERE pod.po_distribution_id=aid.po_distribution_id
    AND   pod.po_line_id = pol.po_line_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''FIXED PRICE'',''RATE'')
    AND   aid.line_type_lookup_code in (''ITEM'',''PREPAY'',''ACCRUAL'')
    AND   poh.po_header_id = pol.po_header_id
    AND   poh.po_header_id = ##$$DOCID$$##
    GROUP BY poh.segment1, pod.po_header_id, pod.po_line_id,
             pod.line_location_id, pod.po_release_id,
             pod.po_distribution_id, nvl(pod.quantity_billed,0),
             nvl(pod.amount_billed,0), pol.order_type_lookup_code
    HAVING round(nvl(pod.amount_billed,0),15) <>
             round(sum(nvl(aid.amount,0)),15)',
    'Mismatched Quantity or Amounts Billed',
    'RS',
    'This document has a mismatch in the quantity or amount billed
     between the shipments or distributions and the values on the invoice
     distributions in Payables',
    'Follow the solution instructions provided in [454060.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 3
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1419114.1';
  add_signature(
   'DATA_SINGLE_POREL3',
   'SELECT DISTINCT ph.po_header_id,
           ph.type_lookup_code,
           pl.po_line_id,
           pll.line_location_id,
           pl.unit_meas_lookup_code,
           pll.unit_meas_lookup_code
    FROM po_line_locations_all pll,
                 po_lines_all pl,
                 po_headers_all ph
    WHERE ph.po_header_id = ##$$DOCID$$##
    AND   nvl(pll.unit_meas_lookup_code, -1) <>
            nvl(pl.unit_meas_lookup_code, -1)
    AND   pll.po_line_id = pl.po_line_id
    AND   pl.po_header_id = ph.po_header_id
    AND   pll.unit_meas_lookup_code IS NOT NULL
    AND   pl.unit_meas_lookup_code IS NOT NULL
    AND   nvl(pll.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(pll.cancel_flag, ''N'') <> ''Y''
    AND   ((ph.type_lookup_code = ''BLANKET'' AND
            pll.po_release_id IS NOT NULL) OR
           ph.type_lookup_code <> ''BLANKET'')',
    'Unit of Measure (UOM) Mismatch',
    'RS',
    'This PO has a mismatch in the unit of measures assigned to the
     the shipments and the lines.',
    'Follow the solution instructions provided in [1419114.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 4
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1379274.1';
  l_info('Bug Number') := '14782923';
  l_info('Script Name') := 'poxpoaprvl.sql';
  add_signature(
   'DATA_SINGLE_POREL4',
   'SELECT po_header_id,
           segment1 po_number,
           org_id,
           cancel_flag,
           authorization_status
    FROM po_headers_all
    WHERE po_header_id = ##$$DOCID$$##
    AND   nvl(cancel_flag, ''N'') = ''Y''
    AND   authorization_status = ''REQUIRES REAPPROVAL''',
    'Canceled PO in REQUIRES REAPPROVAL Status',
    'RS',
    'This purchase order is canceled but the authorization status is
     ''Requires Reapproval''',
    'Follow the solution instructions provided in [1379274.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 5
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1346647.1';
  l_info('Script Name') := 'tax_code_detect.sql';
  add_signature(
    'DATA_SINGLE_POREL5',
   'SELECT ph.po_header_id,
           ph.segment1 po_number,
           pl.line_num,
           pll.line_location_id,
           pll.shipment_num,
           pll.tax_attribute_update_code,
           ''UPDATE'' "Correct Code"
    FROM po_headers_all ph,
         po_lines_all pl,
         po_line_locations_all pll
    WHERE ph.po_header_id = ##$$DOCID$$##
    AND   ph.po_header_id = pll.po_header_id
    AND   pl.po_line_id = pll.po_line_id
    AND   nvl(pll.tax_attribute_update_code,''UPDATE'') <> ''UPDATE''
    AND   EXISTS (
            SELECT 1 FROM zx_lines_det_factors
            WHERE application_id = 201
            AND   entity_code = ''PURCHASE_ORDER''
            AND   trx_id = pll.po_header_id
            AND   trx_line_id = pll.line_location_id)',
    'Incorrect Tax Attribute Update Code - Approval Error',
    'RS',
    'This purchase order has an incorrect value for tax attribute update code.
     This can cause the error Tax exception 023 (ORA-00001: unique constraint
     (ZX.ZX_LINES_DET_FACTORS_U1) violated) when approving.',
    'To correct this data corruption please create a Service Request with
     Oracle Support referencing [1346647.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 6
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1269228.1';
  l_info('Script name') := 'poxaustat.sql';
  add_signature(
    'DATA_SINGLE_POREL6',
   'SELECT ph.po_header_id,
           ph.segment1 po_number,
           ph.authorization_status
    FROM po_headers_all ph
    WHERE ph.po_header_id = ##$$DOCID$$##
    AND   authorization_status = ''REQUIRES_REAPPROVAL''',
    'Invalid Authorization Status',
    'RS',
    'This purchase order has an invalid value for authorization status
     (REQUIRES_REAPPROVAL instead of REQUIRES REAPPROVAL).
     This can result in errors such as the follwing when working in
     the Buyer Work Center and searching agreements for a supplier:<br/>
     <blockquote>Exception Details.<br/>
      oracle.apps.fnd.framework.OAException:
      java.lang.Exception: Assertion failure: The value cannot be null.<br/>
      at oracle.apps.fnd.framework.OAException.wrapperException(OAException.java:896)<br/>
      ...</blockquote>',
    'To correct this data please create a Service Request with Oracle
     Support referencing [1269228.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 7
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '756627.1';
  add_signature(
    'DATA_SINGLE_POREL7',
   'SELECT distinct h.po_header_id,
                    h.segment1 "PO_Number",
                    d.rate "PO Dist Rate",
                    h.currency_code "PO Currency Code",
                    rl.rate "Req Line Rate",
                    rl.currency_code "Req Line Currency",
                    d.creation_date "PO Dist Creation Date",
                    (d.rate/rl.rate) rate_ratio
    FROM po_distributions_all d,
         po_req_distributions_all rd,
         po_requisition_lines_all rl,
         po_headers_all h
    WHERE h.po_header_id = ##$$DOCID$$##
    AND   d.req_distribution_id = rd.distribution_id
    AND   rl.requisition_line_id = rd.requisition_line_id
    AND   rl.rate / d.rate < 0.5
    AND   h.po_header_id = d.po_header_id
    AND   h.currency_code = rl.currency_code
    ORDER BY rl.currency_code',
    'Incorrect Rate on Autocreated PO',
    'RS',
    'Foreign currency autocreated PO''s using the "Specify" option can result in
     the inverse rate being assigned.  This PO has an incorrect rate assigned.',
    'Please review [756627.1]. To correct the data please create a Service
     Request with Oracle Support referencing [756627.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  PO/REL 8
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1280061.1';
  add_signature(
    'DATA_SINGLE_POREL8',
   'SELECT pod.po_header_id,
           poh.segment1 po_number,
           poll.line_location_id,
           poll.ship_to_organization_id,
           pod.po_distribution_id,
           pod.destination_organization_id,
           null supply_source_id,
           null to_organization_id
    FROM po_distributions_all pod,
         po_line_locations_all poll,
         po_headers_all poh
    WHERE poh.po_header_id = ##$$DOCID$$##
    AND   poh.po_header_id = poll.po_header_id
    AND   pod.line_location_id = poll.line_location_id
    AND   pod.po_header_id = poll.po_header_id
    AND   pod.destination_organization_id != poll.ship_to_organization_id
    AND   nvl(poll.closed_code,''OPEN'') != ''FINALLY CLOSED''
    AND   nvl(poll.cancel_flag,''N'') != ''Y''
    UNION
    SELECT poh.po_header_id,
           poh.segment1,
           poll.line_location_id,
           poll.ship_to_organization_id,
           null,
           null,
           mtl.supply_source_id,
           mtl.to_organization_id
    FROM mtl_supply mtl,
         po_line_locations_all poll,
         po_headers_all poh
    WHERE poh.po_header_id = ##$$DOCID$$##
    AND   mtl.supply_type_code = ''PO''
    AND   mtl.po_line_location_id = poll.line_location_id
    AND   mtl.po_header_id = poll.po_header_id
    AND   mtl.to_organization_id != poll.ship_to_organization_id
    AND   nvl(poll.closed_code,''OPEN'') != ''FINALLY CLOSED''
    AND   nvl(poll.cancel_flag,''N'') != ''Y''
    AND   poh.po_header_id = poll.po_header_id',
    'Ship To Organization Mismatch',
    'RS',
    'The ship to organization on the PO does not match the deliver to organization
     on the distributions or in mtl_supply. This can cause approved PO''s
     not to be displayed in Inventory''s Supply/Demand Detail window.',
    'Please review [1280061.1]. To correct the data please create a Service
     Request with Oracle Support referencing [1280061.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  --------------------------------------
  -- Single Trx Data Integrity  REQ 1
  --------------------------------------
  l_info.delete;
  l_info('Doc ID') := '415151.1';
  l_info('Script Name') := 'poxrqesf.sql';
  add_signature(
   'DATA_SINGLE_REQ1',
   'SELECT prl.requisition_header_id,
           prl.requisition_line_id,
           pll.line_location_id,
           prl.modified_by_agent_flag,
           prl.cancel_flag,
           prl.source_type_code
    FROM po_requisition_lines_all prl,
         po_line_locations_all pll
    WHERE prl.requisition_header_id = ##$$DOCID$$##
    AND   prl.line_location_id = pll.line_location_id
    AND   pll.approved_flag = ''Y''
    AND   nvl(prl.cancel_flag,''N'') = ''N''
    AND   nvl(prl.modified_by_agent_flag,''N'') = ''N''
    AND   EXISTS (
            SELECT 1 FROM mtl_supply
            WHERE prl.requisition_line_id = supply_source_id
            AND   supply_type_code = ''REQ'')
    UNION ALL
    SELECT prl.requisition_header_id,
           prl.requisition_line_id,
           to_number(NULL) line_location_id,
           prl.modified_by_agent_flag,

           prl.cancel_flag,
           prl.source_type_code
    FROM po_requisition_lines_all prl
    WHERE prl.requisition_header_id = ##$$DOCID$$##
      AND   (nvl(prl.cancel_flag,''N'') = ''Y'' OR
             (prl.cancel_flag = ''N'' AND
              prl.modified_by_agent_flag = ''Y''))
      AND   EXISTS (
              SELECT 1 FROM mtl_supply
              WHERE prl.requisition_line_id = supply_source_id
              AND   supply_type_code = ''REQ'')',
    'Invalid Supply/Demand for Requisition Lines',
    'RS',
    'This document has canceled or modified requisition lines with invalid
     supply existing in the mtl_supply table.',
    'Follow the solution instructions provided in [415151.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  -----------------------------------
  -- Single Trx Data Integrity  REQ 2
  -----------------------------------
  l_info.delete;
  l_info('Doc ID') := '1220964.1';
  l_info('Script Name') := 'POXIREQF.sql';
  add_signature(
   'DATA_SINGLE_REQ2',
    'SELECT prl.requisition_header_id,
            prl.requisition_line_id,
            to_number(NULL) line_location_id,
            nvl(prl.quantity_delivered, 0),
            prl.quantity
     FROM mtl_supply ms,
          po_requisition_lines_all prl
     WHERE prl.requisition_header_id = ##$$DOCID$$##
     AND   ms.supply_type_code = ''REQ''
     AND   prl.source_type_code=''INVENTORY''
     AND   prl.requisition_line_id = ms.supply_source_id
     AND   nvl(prl.quantity_delivered,0) >= prl.quantity',
    'Fully Received Lines Showing Pending Supply',
    'RS',
    'This requisition has fully received lines which continue to show
     pending supply.',
    'Follow the solution instructions provided in [1220964.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');

  -----------------------------------
  -- Single Trx Data Integrity  REQ 3
  -----------------------------------
  l_info.delete;
  l_info('Doc ID') := '1432915.1';
  l_info('Script Name') := 'return_req_pool.sql';
  add_signature(
   'DATA_SINGLE_REQ3',
   'SELECT rh.requisition_header_id req_header_id,
           rh.segment1 req_number,
           rl.requisition_line_id req_line_id,
           rl.line_num req_line_num,
           rl.line_location_id req_line_loc,
           rl.reqs_in_pool_flag req_pool_flag
    FROM po_requisition_headers_all rh,
         po_requisition_lines_all rl
    WHERE rh.requisition_header_id = ##$$DOCID$$##
    AND   rh.requisition_header_id = rl.requisition_header_id
    AND   rh.authorization_status = ''APPROVED''
    AND   rl.reqs_in_pool_flag is null
    AND   rl.line_location_id is not null
    AND   nvl(rl.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(rl.cancel_flag,''N'') <> ''Y''
    AND   NOT EXISTS (
            SELECT 1 FROM po_line_locations_all ll
            WHERE ll.line_location_id = rl.line_location_id)',
    'Requisition lines not available in Autocreate form after PO deletion.',
    'RS',
    'This requisition has lines which are not available in the Autocreate
     form even after the associated purchase order has been deleted.',
    'Follow the solution instructions provided in [1432915.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');


    
  -------------------------------------------------------
  -- Data issues after upgrade (wf notifications stuck --
  -------------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1532406.1';
  add_signature(
   'UPGRADE_SINGLE',
   'SELECT  wiav.item_type,
            wiav.item_key,
            wiav.NAME,
            wiav.text_value
     FROM   wf_item_attribute_values wiav,
            WF_ITEM_ACTIVITY_STATUSES wias
     WHERE  wiav.NAME IN (''PO_REQ_APPROVE_MSG'',
                     ''PO_REQ_APPROVED_MSG'',
                     ''PO_REQ_NO_APPROVER_MSG'',
                     ''PO_REQ_REJECT_MSG'',
                     ''REQ_LINES_DETAILS'',
                     ''PO_LINES_DETAILS'')
            AND (wiav.text_value LIKE ''PLSQL:%POAPPRV%''
                  OR wiav.text_value LIKE ''PLSQL:%REQAPPRV%'')
            AND wiav.item_key = wias.item_key
            AND wiav.item_type = wias.item_type
            AND wiav.item_key = ''##$$ITMTYPE$$##''
            AND wiav.item_key = ''##$$ITMKEY$$##''
            AND wias.notification_id IN (SELECT notification_id FROM wf_notifications
                                        WHERE message_type IN (''POAPPRV'',''REQAPPRV'')
                                        AND status <> ''CLOSED'')',
    'Document has active revisions created before upgrade',
    'RS',
    'This document has pending revisions that have been created and not closed before the upgrade.',
    'Follow the solution instructions provided in [1532406.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');
    
    
  /*###########################################
    #  Recent Document Data Integrity Checks  #
    ###########################################*/

  ---------------------------------------------
  -- Recent Document Data Integrity GEN1 (MGD1)
  ---------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '795177.1';
  l_info('Script Name') := 'podelorgf.sql';
  add_signature(
   'DATA_RANGE_GEN1',
   'SELECT DISTINCT
           pdtb.document_type_code,
           pdtb.document_subtype,
           pdtb.org_id
    FROM po_document_types_all_b pdtb,
         po_document_types_all_tl pdtt
    WHERE pdtb.org_id IS NULL
    AND   pdtt.org_id IS NULL
    AND   pdtb.document_type_code = pdtt.document_type_code
    AND   pdtb.document_subtype = pdtt.document_subtype
    AND   pdtb.last_update_date >= to_date(''##$$FDATE$$##'')',
    'Document Types with Null Org_ID',
    'RS',
    'There are document types with a null org_id assigned.  This can result
     in PO distribution lines displaying twice in the Purchase Order Summary
     form.',
    'Follow the solution instructions provided in [795177.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -----------------------------------------------
  -- Recent Document Data Integrity PO 1 (MGD2-1)
  -----------------------------------------------
  add_signature(
   'DATA_RANGE_PO1',
   'SELECT h.segment1 po_number,
           h.type_lookup_code type_lookup_code,
           h.po_header_id,
           h.revision_num,
           h.creation_date,
           CASE 
               WHEN h.vendor_site_id <> ha.vendor_site_id THEN ''VENDOR_SITE_ID''
               WHEN (h.vendor_site_id IS NULL AND ha.vendor_site_id IS NOT NULL) THEN ''VENDOR_SITE_ID''
               WHEN (h.vendor_site_id IS NOT NULL AND ha.vendor_site_id IS NULL) THEN ''VENDOR_SITE_ID''
               WHEN h.vendor_contact_id <> ha.vendor_contact_id THEN ''VENDOR_CONTACT_ID''
               WHEN (h.vendor_contact_id IS NULL AND ha.vendor_contact_id IS NOT NULL) THEN ''VENDOR_CONTACT_ID''
               WHEN (h.vendor_contact_id IS NOT NULL AND ha.vendor_contact_id IS NULL) THEN ''VENDOR_CONTACT_ID''
               WHEN h.ship_to_location_id <> ha.ship_to_location_id THEN ''SHIP_TO_LOCATION_ID''
               WHEN (h.ship_to_location_id IS NULL AND ha.ship_to_location_id IS NOT NULL) THEN ''SHIP_TO_LOCATION_ID''
               WHEN (h.ship_to_location_id IS NOT NULL AND ha.ship_to_location_id IS NULL) THEN ''SHIP_TO_LOCATION_ID''
               WHEN h.bill_to_location_id <> ha.bill_to_location_id THEN ''BILL_TO_LOCATION_ID''
               WHEN (h.bill_to_location_id IS NULL AND ha.bill_to_location_id IS NOT NULL) THEN ''BILL_TO_LOCATION_ID''
               WHEN (h.bill_to_location_id IS NOT NULL AND ha.bill_to_location_id IS NULL) THEN ''BILL_TO_LOCATION_ID''
               WHEN h.terms_id <> ha.terms_id THEN ''TERMS_ID''
               WHEN (h.terms_id IS NULL AND ha.terms_id IS NOT NULL) THEN ''TERMS_ID''
               WHEN (h.terms_id IS NOT NULL AND ha.terms_id IS NULL) THEN ''TERMS_ID''
               WHEN h.ship_via_lookup_code <> ha.ship_via_lookup_code THEN ''SHIP_VIA_LOOKUP_CODE''
               WHEN  (h.ship_via_lookup_code IS NULL AND ha.ship_via_lookup_code IS NOT NULL) THEN ''SHIP_VIA_LOOKUP_CODE''
               WHEN  (h.ship_via_lookup_code IS NOT NULL AND ha.ship_via_lookup_code IS NULL) THEN ''SHIP_VIA_LOOKUP_CODE''
               WHEN (h.fob_lookup_code <> ha.fob_lookup_code) THEN ''FOB_LOOKUP_CODE''
               WHEN  (h.fob_lookup_code IS NULL AND ha.fob_lookup_code IS NOT NULL) THEN ''FOB_LOOKUP_CODE''
               WHEN  (h.fob_lookup_code IS NOT NULL AND ha.fob_lookup_code IS NULL) THEN ''FOB_LOOKUP_CODE''
               WHEN (h.freight_terms_lookup_code <> ha.freight_terms_lookup_code) THEN ''FREIGHT_TERMS_LOOKUP_CODE''
               WHEN  (h.freight_terms_lookup_code IS NULL AND ha.freight_terms_lookup_code IS NOT NULL) THEN ''FREIGHT_TERMS_LOOKUP_CODE''
               WHEN  (h.freight_terms_lookup_code IS NOT NULL AND ha.freight_terms_lookup_code IS NULL) THEN ''FREIGHT_TERMS_LOOKUP_CODE''
               WHEN (h.shipping_control <> ha.shipping_control) THEN ''SHIPPING_CONTROL''
               WHEN  (h.shipping_control IS NULL AND ha.shipping_control IS NOT NULL) THEN ''SHIPPING_CONTROL''
               WHEN  (h.shipping_control IS NOT NULL AND ha.shipping_control IS NULL) THEN ''SHIPPING_CONTROL''
               WHEN (h.blanket_total_amount <> ha.blanket_total_amount) THEN ''BLANKET_TOTAL_AMOUNT''
               WHEN  (h.blanket_total_amount IS NULL AND ha.blanket_total_amount IS NOT NULL) THEN ''BLANKET_TOTAL_AMOUNT''
               WHEN  (h.blanket_total_amount IS NOT NULL AND ha.blanket_total_amount IS NULL) THEN ''BLANKET_TOTAL_AMOUNT''
               WHEN (h.note_to_vendor <> ha.note_to_vendor) THEN ''NOTE_TO_VENDOR''
               WHEN  (h.note_to_vendor IS NULL AND ha.note_to_vendor IS NOT NULL) THEN ''NOTE_TO_VENDOR''
               WHEN  (h.note_to_vendor IS NOT NULL AND ha.note_to_vendor IS NULL) THEN ''NOTE_TO_VENDOR''
               WHEN (h.confirming_order_flag <> ha.confirming_order_flag) THEN ''CONFIRMING_ORDER_FLAG''
               WHEN  (h.confirming_order_flag IS NULL AND ha.confirming_order_flag IS NOT NULL) THEN ''CONFIRMING_ORDER_FLAG''
               WHEN  (h.confirming_order_flag IS NOT NULL AND ha.confirming_order_flag IS NULL) THEN ''CONFIRMING_ORDER_FLAG''
               WHEN ((h.acceptance_required_flag <> ha.acceptance_required_flag) AND (h.acceptance_required_flag <> ''N'')) THEN ''ACCEPTANCE_REQUIRED_FLAG''
               WHEN  (ha.acceptance_required_flag in (''Y'',''D'') AND h.acceptance_required_flag = ''N'' AND nvl(a.accepted_flag,''X'') <> ''Y'') THEN ''ACCEPTANCE_REQUIRED_FLAG''
               WHEN  (h.acceptance_required_flag IS NULL AND ha.acceptance_required_flag IS NOT NULL) THEN ''ACCEPTANCE_REQUIRED_FLAG''
               WHEN  (h.acceptance_required_flag IS NOT NULL AND ha.acceptance_required_flag IS NULL) THEN ''ACCEPTANCE_REQUIRED_FLAG''
               WHEN (h.acceptance_due_date <> ha.acceptance_due_date) THEN ''ACCEPTANCE_DUE_DATE''
               WHEN  (h.acceptance_due_date IS NULL AND ha.acceptance_due_date IS NOT NULL AND nvl(a.accepted_flag,''N'') = ''N'' 
                          AND nvl(h.acceptance_required_flag, ''X'') <> ''S'') THEN ''ACCEPTANCE_DUE_DATE'' 
               WHEN  (h.acceptance_due_date IS NOT NULL AND ha.acceptance_due_date IS NULL) THEN ''ACCEPTANCE_DUE_DATE''
               WHEN (h.amount_limit <> ha.amount_limit) THEN ''AMOUNT_LIMIT''
               WHEN  (h.amount_limit IS NULL AND ha.amount_limit IS NOT NULL) THEN ''AMOUNT_LIMIT''
               WHEN  (h.amount_limit IS NOT NULL AND ha.amount_limit IS NULL) THEN ''AMOUNT_LIMIT''
               WHEN (h.start_date <> ha.start_date) THEN ''START_DATE''
               WHEN  (h.start_date IS NULL AND ha.start_date IS NOT NULL) THEN ''START_DATE''
               WHEN  (h.start_date IS NOT NULL AND ha.start_date IS NULL) THEN ''START_DATE''
               WHEN (h.end_date <> ha.end_date) THEN ''END_DATE''
               WHEN  (h.end_date IS NULL AND ha.end_date IS NOT NULL) THEN ''END_DATE''
               WHEN  (h.end_date IS NOT NULL AND ha.end_date IS NULL) THEN ''END_DATE''
               WHEN (h.cancel_flag <> ha.cancel_flag) THEN ''CANCEL_FLAG''
               WHEN  (h.cancel_flag IS NULL AND ha.cancel_flag IS NOT NULL) THEN ''CANCEL_FLAG''
               WHEN  (h.cancel_flag IS NOT NULL AND ha.cancel_flag IS NULL) THEN ''CANCEL_FLAG''
               WHEN (h.conterms_articles_upd_date <> ha.conterms_articles_upd_date) THEN ''CONTERMS_ARTICLES_UPD_DATE''
               WHEN  (h.conterms_articles_upd_date IS NULL AND ha.conterms_articles_upd_date IS NOT NULL) THEN ''CONTERMS_ARTICLES_UPD_DATE''
               WHEN  (h.conterms_articles_upd_date IS NOT NULL AND ha.conterms_articles_upd_date IS NULL) THEN ''CONTERMS_ARTICLES_UPD_DATE''
               WHEN (h.conterms_deliv_upd_date <> ha.conterms_deliv_upd_date) THEN ''CONTERMS_DELIV_UPD_DATE''
               WHEN  (h.conterms_deliv_upd_date IS NULL AND ha.conterms_deliv_upd_date IS NOT NULL) THEN ''CONTERMS_DELIV_UPD_DATE''
               WHEN  (h.conterms_deliv_upd_date IS NOT NULL AND ha.conterms_deliv_upd_date IS NULL) THEN ''CONTERMS_DELIV_UPD_DATE''
    END AS Mismatched_column
    FROM po_headers_all h,
         po_headers_archive_all ha,
         po_acceptances a,
         po_document_types_all dt
    WHERE h.type_lookup_code in (''STANDARD'',''CONTRACT'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status = ''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code = dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num = ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.po_header_id = a.po_header_id(+)
    AND   a.revision_num (+) = h.revision_num
    AND   a.accepted_flag(+) = ''Y''
    AND   (((h.vendor_site_id <> ha.vendor_site_id) OR
           (h.vendor_site_id IS NULL AND ha.vendor_site_id IS NOT NULL) OR
           (h.vendor_site_id IS NOT NULL AND ha.vendor_site_id IS NULL)) OR
          ((h.vendor_contact_id <> ha.vendor_contact_id) OR
           (h.vendor_contact_id IS NULL AND ha.vendor_contact_id IS NOT NULL) OR
           (h.vendor_contact_id IS NOT NULL AND ha.vendor_contact_id IS NULL)) OR
          ((h.ship_to_location_id <> ha.ship_to_location_id) OR
           (h.ship_to_location_id IS NULL AND ha.ship_to_location_id IS NOT NULL) OR
           (h.ship_to_location_id IS NOT NULL AND ha.ship_to_location_id IS NULL)) OR
          ((h.bill_to_location_id <> ha.bill_to_location_id) OR
           (h.bill_to_location_id IS NULL AND ha.bill_to_location_id IS NOT NULL) OR
           (h.bill_to_location_id IS NOT NULL AND ha.bill_to_location_id IS NULL)) OR
          ((h.terms_id <> ha.terms_id) OR
           (h.terms_id IS NULL AND ha.terms_id IS NOT NULL) OR
           (h.terms_id IS NOT NULL AND ha.terms_id IS NULL)) OR
          ((h.ship_via_lookup_code <> ha.ship_via_lookup_code) OR
           (h.ship_via_lookup_code IS NULL AND ha.ship_via_lookup_code IS NOT NULL) OR
           (h.ship_via_lookup_code IS NOT NULL AND ha.ship_via_lookup_code IS NULL)) OR
          ((h.fob_lookup_code <> ha.fob_lookup_code) OR
           (h.fob_lookup_code IS NULL AND ha.fob_lookup_code IS NOT NULL) OR
           (h.fob_lookup_code IS NOT NULL AND ha.fob_lookup_code IS NULL)) OR
          ((h.freight_terms_lookup_code <> ha.freight_terms_lookup_code) OR
           (h.freight_terms_lookup_code IS NULL AND
            ha.freight_terms_lookup_code IS NOT NULL) OR
           (h.freight_terms_lookup_code IS NOT NULL AND
            ha.freight_terms_lookup_code IS NULL)) OR
          ((h.shipping_control <> ha.shipping_control) OR
           (h.shipping_control IS NULL AND ha.shipping_control IS NOT NULL) OR
           (h.shipping_control IS NOT NULL AND ha.shipping_control IS NULL)) OR
          ((h.blanket_total_amount <> ha.blanket_total_amount) OR
           (h.blanket_total_amount IS NULL AND ha.blanket_total_amount IS NOT NULL) OR
           (h.blanket_total_amount IS NOT NULL AND ha.blanket_total_amount IS NULL)) OR
          ((h.note_to_vendor <> ha.note_to_vendor) OR
           (h.note_to_vendor IS NULL AND ha.note_to_vendor IS NOT NULL) OR
           (h.note_to_vendor IS NOT NULL AND ha.note_to_vendor IS NULL)) OR
          ((h.confirming_order_flag <> ha.confirming_order_flag) OR
           (h.confirming_order_flag IS NULL AND ha.confirming_order_flag IS NOT NULL) OR
           (h.confirming_order_flag IS NOT NULL AND ha.confirming_order_flag IS NULL)) OR
          (((h.acceptance_required_flag <> ha.acceptance_required_flag) AND
            (h.acceptance_required_flag <> ''N'')) OR
           (ha.acceptance_required_flag in (''Y'',''D'') AND
            h.acceptance_required_flag = ''N'' AND
            (nvl(a.accepted_flag,''X'') <> ''Y'')) OR
           (h.acceptance_required_flag IS NULL AND
            ha.acceptance_required_flag IS NOT NULL) OR
           (h.acceptance_required_flag IS NOT NULL AND
            ha.acceptance_required_flag IS NULL)) OR
          ((h.acceptance_due_date <> ha.acceptance_due_date) OR
           (h.acceptance_due_date IS NULL AND ha.acceptance_due_date IS NOT NULL AND
            nvl(a.accepted_flag,''N'') = ''N'' AND
            nvl(h.acceptance_required_flag, ''X'') <> ''S'') OR
           (h.acceptance_due_date IS NOT NULL AND ha.acceptance_due_date IS NULL)) OR
          ((h.amount_limit <> ha.amount_limit) OR
           (h.amount_limit IS NULL AND ha.amount_limit IS NOT NULL) OR
           (h.amount_limit IS NOT NULL AND ha.amount_limit IS NULL)) OR
          ((h.start_date <> ha.start_date) OR
           (h.start_date IS NULL AND ha.start_date IS NOT NULL) OR
           (h.start_date IS NOT NULL AND ha.start_date IS NULL)) OR
          ((h.end_date <> ha.end_date) OR
           (h.end_date IS NULL AND ha.end_date IS NOT NULL) OR
           (h.end_date IS NOT NULL AND ha.end_date IS NULL)) OR
          ((h.cancel_flag <> ha.cancel_flag) OR
           (h.cancel_flag IS NULL AND ha.cancel_flag IS NOT NULL) OR
           (h.cancel_flag IS NOT NULL AND ha.cancel_flag IS NULL)) OR
          ((h.conterms_articles_upd_date <> ha.conterms_articles_upd_date) OR
           (h.conterms_articles_upd_date IS NULL AND
            ha.conterms_articles_upd_date IS NOT NULL) OR
           (h.conterms_articles_upd_date IS NOT NULL AND
            ha.conterms_articles_upd_date IS NULL)) OR
          ((h.conterms_deliv_upd_date <> ha.conterms_deliv_upd_date) OR
           (h.conterms_deliv_upd_date IS NULL AND
            ha.conterms_deliv_upd_date IS NOT NULL) OR
           (h.conterms_deliv_upd_date IS NOT NULL AND
            ha.conterms_deliv_upd_date IS NULL)))
    AND   h.org_id = ##$$ORGID$$##
    AND   h.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Headers Archive',
    'RS',
    'There are data discrepancies between PO_HEADERS_ALL and PO_HEADERS_ARCHIVE_ALL
     for this PO, which can result in issues trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');
    
  -----------------------------------------------
  -- Recent Document Data Integrity PO 2 (MGD2-2)
  -----------------------------------------------
  add_signature(
   'DATA_RANGE_PO2',
   'SELECT h.segment1 PO_NUMBER,
           h.type_lookup_code type_lookup_code,
           l.po_header_id,
           l.po_line_id ,
           h.revision_num,
           l.line_num,
           la.base_unit_price,
           l.creation_date,
           l.last_update_date
    FROM po_lines_all l,
         po_lines_archive_all la,
         po_headers_all h ,
         po_headers_archive_all ha ,
         po_document_types_all dt
    WHERE h.po_header_id = l.po_header_id
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status=''APPROVED''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   l.po_line_id = la.po_line_id
    AND   la.latest_external_flag  = ''Y''
    AND   ((l.line_num <> la.line_num) OR
           ((l.item_id <> la.item_id) OR
            (l.item_id IS NULL AND la.item_id IS NOT NULL) OR
            (l.item_id IS NOT NULL AND   la.item_id IS NULL)) OR
           ((l.job_id <> la.job_id) OR
            (l.job_id IS NULL AND la.job_id IS NOT NULL) OR
            (l.job_id IS NOT NULL AND la.job_id IS NULL)) OR
           ((l.amount <> la.amount) OR
            (l.amount IS NULL AND la.amount IS NOT NULL) OR
            (l.amount IS NOT NULL AND la.amount IS NULL)) OR
           ((trunc(l.expiration_date) <> trunc(la.expiration_date)) OR
            (l.expiration_date IS NULL AND la.expiration_date IS NOT NULL) OR
            (l.expiration_date IS NOT NULL AND   la.expiration_date IS NULL)) OR
           ((trunc(l.start_date) <> trunc(la.start_date)) OR
            (l.start_date IS NULL AND la.start_date IS NOT NULL) OR
            (l.start_date IS NOT NULL AND la.start_date IS NULL)) OR
           ((l.contractor_first_name <> la.contractor_first_name) OR
            (l.contractor_first_name IS NULL AND la.contractor_first_name IS NOT NULL) OR
            (l.contractor_first_name IS NOT NULL AND la.contractor_first_name IS NULL)) OR
           ((l.contractor_last_name <> la.contractor_last_name) OR
            (l.contractor_last_name IS NULL AND la.contractor_last_name IS NOT NULL) OR
            (l.contractor_last_name IS NOT NULL AND la.contractor_last_name IS NULL)) OR
           ((l.item_revision <> la.item_revision) OR
            (l.item_revision IS NULL AND la.item_revision IS NOT NULL) OR
            (l.item_revision IS NOT NULL AND la.item_revision IS NULL)) OR
           ((l.item_description <> la.item_description) OR
            (l.item_description IS NULL AND la.item_description IS NOT NULL) OR
            (l.item_description IS NOT NULL AND la.item_description IS NULL)) OR
           ((l.unit_meas_lookup_code <> la.unit_meas_lookup_code) OR
            (l.unit_meas_lookup_code IS NULL AND la.unit_meas_lookup_code IS NOT NULL) OR
            (l.unit_meas_lookup_code IS NOT NULL AND la.unit_meas_lookup_code IS NULL)) OR
           ((l.quantity <> la.quantity) OR
            (l.quantity IS NULL AND la.quantity IS NOT NULL) OR
            (l.quantity IS NOT NULL AND la.quantity IS NULL)) OR
           ((l.quantity_committed <> la.quantity_committed) OR
            (l.quantity_committed IS NULL AND la.quantity_committed IS NOT NULL) OR
            (l.quantity_committed IS NOT NULL AND la.quantity_committed IS NULL)) OR
           ((l.committed_amount <> la.committed_amount) OR
            (l.committed_amount IS NULL AND la.committed_amount IS NOT NULL) OR
            (l.committed_amount IS NOT NULL AND la.committed_amount IS NULL)) OR
           ((l.unit_price <> la.unit_price) OR
            (l.unit_price IS NULL AND la.unit_price IS NOT NULL) OR
            (l.unit_price IS NOT NULL AND la.unit_price IS NULL)) OR
           ((l.not_to_exceed_price <> la.not_to_exceed_price) OR
            (l.not_to_exceed_price IS NULL AND la.not_to_exceed_price IS NOT NULL) OR
            (l.not_to_exceed_price IS NOT NULL AND la.not_to_exceed_price IS NULL)) OR
           ((l.un_number_id <> la.un_number_id) OR
            (l.un_number_id IS NULL AND la.un_number_id IS NOT NULL) OR
            (l.un_number_id IS NOT NULL AND la.un_number_id IS NULL)) OR
           ((l.hazard_class_id <> la.hazard_class_id) OR
            (l.hazard_class_id IS NULL AND la.hazard_class_id IS NOT NULL) OR
            (l.hazard_class_id IS NOT NULL AND la.hazard_class_id IS NULL)) OR
           ((l.note_to_vendor <> la.note_to_vendor) OR
            (l.note_to_vendor IS NULL AND la.note_to_vendor IS NOT NULL) OR
            (l.note_to_vendor IS NOT NULL AND la.note_to_vendor IS NULL)) OR
           ((l.note_to_vendor <> la.note_to_vendor) OR
            (l.note_to_vendor IS NULL AND la.note_to_vendor IS NOT NULL) OR
            (l.note_to_vendor IS NOT NULL AND la.note_to_vendor IS NULL)) OR
           ((l.from_header_id <> la.from_header_id) OR
            (l.from_header_id IS NULL AND la.from_header_id IS NOT NULL) OR
            (l.from_header_id IS NOT NULL AND la.from_header_id IS NULL)) OR
           ((l.from_line_id <> la.from_line_id) OR
            (l.from_line_id IS NULL AND la.from_line_id IS NOT NULL) OR
            (l.from_line_id IS NOT NULL AND la.from_line_id IS NULL)) OR
           ((l.vendor_product_num <> la.vendor_product_num) OR
            (l.vendor_product_num IS NULL AND la.vendor_product_num IS NOT NULL) OR
            (l.vendor_product_num IS NOT NULL AND la.vendor_product_num IS NULL)) OR
           ((l.contract_id <> la.contract_id) OR
            (l.contract_id IS NULL AND la.contract_id IS NOT NULL) OR
            (l.contract_id IS NOT NULL AND la.contract_id IS NULL)) OR
           ((l.price_type_lookup_code <> la.price_type_lookup_code) OR
            (l.price_type_lookup_code IS NULL AND
             la.price_type_lookup_code IS NOT NULL) OR
            (l.price_type_lookup_code IS NOT NULL AND
             la.price_type_lookup_code IS NULL)) OR
           ((l.cancel_flag <> la.cancel_flag) OR
            (l.cancel_flag IS NULL AND la.cancel_flag IS NOT NULL) OR
            (l.cancel_flag IS NOT NULL AND la.cancel_flag IS NULL)))
    AND   h.org_id = ##$$ORGID$$##
    AND   l.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Lines Archive',
    'RS',
    'There are data discrepancies between PO_LINES_ALL and PO_LINES_ARCHIVE_ALL
     for this PO, which can result in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  -----------------------------------------------
  -- Recent Document Data Integrity PO 3 (MGD2-3)
  -----------------------------------------------
  add_signature(
   'DATA_RANGE_PO3',
   'SELECT h.segment1 po_number,
           ll.shipment_type type_lookup_code,
           ll.po_header_id,
           ll.po_line_id,
           ll.line_location_id,
           h.revision_num,
           ll.creation_date,
           ll.last_update_date
    FROM po_line_locations_all ll,
         po_line_locations_archive_all lla,
         po_headers_all h,
         po_headers_archive_all ha,
         po_document_types_all dt
    WHERE h.po_header_id=ll.po_header_id
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'',''BLANKET'')
    AND   h.authorization_status=''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   ll.po_release_id is null
    AND   ll.line_location_id = lla.line_location_id
    AND   lla.latest_external_flag  = ''Y''
    AND   (((ll.quantity <> lla.quantity) OR
            (ll.quantity IS NULL AND lla.quantity IS NOT NULL) OR
            (ll.quantity IS NOT NULL AND lla.quantity IS NULL)) OR
           ((ll.amount <> lla.amount) OR
            (ll.amount IS NULL AND lla.amount IS NOT NULL) OR
            (ll.amount IS NOT NULL AND lla.amount IS NULL)) OR
           ((ll.ship_to_location_id <> lla.ship_to_location_id) OR
            (ll.ship_to_location_id IS NULL AND lla.ship_to_location_id IS NOT NULL) OR
            (ll.ship_to_location_id IS NOT NULL AND lla.ship_to_location_id IS NULL)) OR
           ((ll.need_by_date <> lla.need_by_date) OR
            (ll.need_by_date IS NULL AND lla.need_by_date IS NOT NULL) OR
            (ll.need_by_date IS NOT NULL AND lla.need_by_date IS NULL)) OR
           ((ll.promised_date <> lla.promised_date) OR
            (ll.promised_date IS NULL AND lla.promised_date IS NOT NULL) OR
            (ll.promised_date IS NOT NULL AND lla.promised_date IS NULL)) OR
           ((ll.last_accept_date <> lla.last_accept_date) OR
            (ll.last_accept_date IS NULL AND lla.last_accept_date IS NOT NULL) OR
            (ll.last_accept_date IS NOT NULL AND lla.last_accept_date IS NULL)) OR
           ((ll.price_override <> lla.price_override) OR
            (ll.price_override IS NULL AND lla.price_override IS NOT NULL) OR
            (ll.price_override IS NOT NULL AND lla.price_override IS NULL)) OR
           ((ll.tax_code_id <> lla.tax_code_id) OR
            (ll.tax_code_id IS NULL AND lla.tax_code_id IS NOT NULL) OR
            (ll.tax_code_id IS NOT NULL AND lla.tax_code_id IS NULL)) OR
           ((ll.shipment_num <> lla.shipment_num) OR
            (ll.shipment_num IS NULL AND lla.shipment_num IS NOT NULL) OR
            (ll.shipment_num IS NOT NULL AND lla.shipment_num IS NULL)) OR
           ((ll.sales_order_update_date <> lla.sales_order_update_date) OR
            (ll.sales_order_update_date IS NULL AND
             lla.sales_order_update_date IS NOT NULL) OR
            (ll.sales_order_update_date IS NOT NULL AND
             lla.sales_order_update_date IS NULL)) OR
           ((ll.cancel_flag <> lla.cancel_flag) OR
            (ll.cancel_flag IS NULL AND lla.cancel_flag IS NOT NULL) OR
            (ll.cancel_flag IS NOT NULL AND lla.cancel_flag IS NULL)) OR
           ((ll.start_date <> lla.start_date) OR
            (ll.start_date is null AND lla.start_date is not null) OR
            (ll.start_date is not null AND lla.start_date is null)) OR
           ((ll.end_date <> lla.end_date) OR
            (ll.end_date is null AND lla.end_date is not null) OR
            (ll.end_date is not null AND lla.end_date is null)))
    AND   h.org_id = ##$$ORGID$$##
    AND   h.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Line Locations Archive',
    'RS',
    'There are data discrepancies between PO_LINES_LOCATIONS_ALL and
     PO_LINE_LOCATIONS_ARCHIVE_ALL for this PO, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  ----------------------------------------------
  -- Recent Document Data Integrity PO 4 (MGD2-4)
  ----------------------------------------------
  add_signature(
   'DATA_RANGE_PO4',
   'SELECT h.segment1 PO_NUMBER,
           h.type_lookup_code type_lookup_code,
           d.po_header_id,
           d.po_line_id,
           d.line_location_id,
           d.po_distribution_id,
           h.revision_num,
           d.creation_date,
           d.last_update_date
    FROM po_distributions_all d,
         po_distributions_archive_all da,
         po_headers_all h,
         po_headers_archive_all ha,
         po_document_types_all dt
    WHERE h.po_header_id = d.po_header_id
    AND   d.po_release_id  is NULL
    AND   h.type_lookup_code in (''STANDARD'',''PLANNED'')
    AND   h.authorization_status=''APPROVED''
    AND   nvl(h.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   h.po_header_id = ha.po_header_id
    AND   ha.latest_external_flag = ''Y''
    AND   h.org_id = dt.org_id
    AND   h.type_lookup_code=dt.document_subtype
    AND   dt.document_type_code in (''PO'',''PA'')
    AND   h.revision_num=ha.revision_num
    AND   nvl(h.cancel_flag,''N'') <> ''Y''
    AND   d.po_distribution_id = da.po_distribution_id
    AND   da.latest_external_flag  = ''Y''
    AND   (((d.quantity_ordered <> da.quantity_ordered) OR
            (d.quantity_ordered IS NULL AND da.quantity_ordered IS NOT NULL) OR
            (d.quantity_ordered IS NOT NULL AND da.quantity_ordered IS NULL)) OR
           ((d.amount_ordered <> da.amount_ordered) OR
            (d.amount_ordered IS NULL AND da.amount_ordered IS NOT NULL) OR
            (d.amount_ordered IS NOT NULL AND da.amount_ordered IS NULL)) OR
           ((d.deliver_to_person_id <> da.deliver_to_person_id) OR
            (d.deliver_to_person_id IS NULL AND da.deliver_to_person_id IS NOT NULL) OR
            (d.deliver_to_person_id IS NOT NULL AND da.deliver_to_person_id IS NULL)) OR
           ((d.recovery_rate <> da.recovery_rate) OR
            (d.recovery_rate IS NULL AND da.recovery_rate IS NOT NULL) OR
            (d.recovery_rate IS NOT NULL AND da.recovery_rate IS NULL)))
    AND   h.org_id = ##$$DOCID$$##
    AND   h.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Distributions Archive',
    'RS',
    'There are data discrepancies between PO_DISTRIBUTIONS_ALL and
     PO_DISTRIBUTIONS_ARCHIVE_ALL for this PO, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  ---------------------------------------------
  -- Recent Document Data Integrity  PO 5 (MGD5)
  ---------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '465068.1';
  add_signature(
   'DATA_RANGE_PO5',
   'SELECT h.segment1 po_number,
           h.org_id,
           h.po_header_id,
           ''Purchase Order'',
           pol.po_line_id,
           pol.line_num
    FROM po_headers_all h,
         po_lines_all pol
    WHERE h.po_header_id = pol.po_header_id
    AND   h.org_id = ##$$ORGID$$##
    AND   pol.creation_date >= to_date(''##$$FDATE$$##'')
    AND   pol.org_id = h.org_id
    AND   EXISTS (
              SELECT ll.po_line_id
              FROM po_line_locations_all ll,
                   po_system_parameters_all sp
              WHERE ll.po_line_id = pol.po_line_id
              AND   ll.shipment_type in (''STANDARD'',''BLANKET'')
              AND   ll.po_release_id is null
              AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                     (1 - nvl(ll.receive_close_tolerance,
                      nvl(sp.receive_close_tolerance,0))/100)) -
                    decode(sp.receive_close_code,
                      ''ACCEPTED'', nvl(ll.quantity_accepted,0),
                      ''DELIVERED'', (
                         SELECT sum(nvl(d1.quantity_delivered,0))
                         FROM po_distributions_all d1
                         WHERE d1.line_location_id= ll.line_location_id),
                      nvl(ll.quantity_received,0)) <= 0.000000000000001
              AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                     (1 - nvl(ll.invoice_close_tolerance,
                            nvl(sp.invoice_close_tolerance,0))/100 )) -
                    nvl(ll.quantity_billed,0) <= 0.000000000000001
              AND   nvl(ll.closed_code,''OPEN'') IN (
                      ''OPEN'',''CLOSED FOR RECEIVING'',''CLOSED FOR INVOICE''))
    ORDER BY h.org_id, h.po_header_id, pol.po_line_id',
    'PO Shipments Eligible to be Closed',
    'RS',
    'This purchase order has shipments which are not closed but which are
     fully received and billed.',
    'Follow the solution instructions provided in [465068.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ------------------------------------------------
  -- Recent Document Data Integrity REL 1 (MGD2-5)
  ------------------------------------------------
  add_signature(
   'DATA_RANGE_REL1',
   'SELECT r.po_release_id,
           r.release_num,
           r.release_date,
           r.po_header_id,
           r.shipping_control,
           r.acceptance_required_flag ,
           r.acceptance_due_date,
           to_char(r.creation_date,
             ''DD-MON-RRRR HH24:MI:SS'') creation_date,
           to_char(r.last_update_date,
             ''DD-MON-RRRR HH24:MI:SS'') last_update_date
    FROM po_releases_all r,
         po_releases_archive_all ra,
         po_acceptances a,
         po_document_types_all dt
    WHERE r.po_release_id = ra.po_release_id
    AND   r.authorization_status = ''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type = dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num = ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   r.po_release_id = a.po_release_id(+)
    AND   a.revision_num (+) = r.revision_num
    AND   a.accepted_flag(+) = ''Y''
    AND   ra.latest_external_flag = ''Y''
    AND   ((r.release_num <> ra.release_num) OR
           (r.release_date <> ra.release_date) OR
           ((r.shipping_control <> ra.shipping_control) OR
            (r.shipping_control IS NULL AND ra.shipping_control IS NOT NULL) OR
            (r.shipping_control IS NOT NULL AND ra.shipping_control IS NULL)) OR
           (((r.acceptance_required_flag <> ra.acceptance_required_flag) AND NOT
             (nvl(r.acceptance_required_flag,''X'') = ''N'' AND
              nvl(ra.acceptance_required_flag,''X'') = ''Y'' AND
              nvl(a.accepted_flag,''X'') = ''Y'')) OR
            (r.acceptance_required_flag = ''Y'' AND
             ra.acceptance_required_flag = ''Y'' AND
             nvl(a.accepted_flag,''X'') = ''Y'') OR
            (r.acceptance_required_flag IS NULL AND
             ra.acceptance_required_flag IS NOT NULL) OR
            (r.acceptance_required_flag IS NOT NULL AND
             ra.acceptance_required_flag IS NULL)) OR
           ((r.acceptance_due_date <> ra.acceptance_due_date) OR
            (r.acceptance_due_date IS NULL AND
             ra.acceptance_due_date IS NOT NULL
             AND nvl(a.accepted_flag,''N'') = ''N'') OR
            (r.acceptance_due_date IS NOT NULL AND
             ra.acceptance_due_date IS NULL)))
    AND   r.org_id = ##$$ORGID$$##
    AND   r.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Releases Archive',
    'RS',
    'There are data discrepancies between PO_RELEASES_ALL and
     PO_RELEASES_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  ------------------------------------------------
  -- Recent Document Data Integrity REL 2 (MGD2-6)
  ------------------------------------------------
  add_signature(
   'DATA_RANGE_REL2',
   'SELECT r.po_release_id,
           r.release_type type_lookup_code,
           ll.po_header_id,
           ll.po_line_id,
           ll.line_location_id,
           r.revision_num,
           ll.creation_date,
           ll.last_update_date
    FROM po_line_locations_all ll,
         po_line_locations_archive_all lla,
         po_releases_all r,
         po_releases_archive_all ra  ,
         po_document_types_all dt
    WHERE r.po_release_id=ll.po_release_id
    AND   r.po_release_id = ra.po_release_id
    AND   ra.latest_external_flag = ''Y''
    AND   r.authorization_status=''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type = dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num = ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   ll.line_location_id = lla.line_location_id
    AND   lla.latest_external_flag  = ''Y''
    AND   (((ll.quantity <> lla.quantity) OR
            (ll.quantity IS NULL AND lla.quantity IS NOT NULL) OR
            (ll.quantity IS NOT NULL AND lla.quantity IS NULL)) OR
           ((ll.amount <> lla.amount) OR
            (ll.amount IS NULL AND lla.amount IS NOT NULL) OR
            (ll.amount IS NOT NULL AND lla.amount IS NULL)) OR
           ((ll.ship_to_location_id <> lla.ship_to_location_id) OR
            (ll.ship_to_location_id IS NULL AND lla.ship_to_location_id IS NOT NULL) OR
            (ll.ship_to_location_id IS NOT NULL AND lla.ship_to_location_id IS NULL)) OR
           ((ll.need_by_date <> lla.need_by_date) OR
            (ll.need_by_date IS NULL AND lla.need_by_date IS NOT NULL) OR
            (ll.need_by_date IS NOT NULL AND lla.need_by_date IS NULL)) OR
           ((ll.promised_date <> lla.promised_date) OR
            (ll.promised_date IS NULL AND lla.promised_date IS NOT NULL) OR
            (ll.promised_date IS NOT NULL AND lla.promised_date IS NULL)) OR
           ((ll.last_accept_date <> lla.last_accept_date) OR
            (ll.last_accept_date IS NULL AND lla.last_accept_date IS NOT NULL) OR
            (ll.last_accept_date IS NOT NULL AND lla.last_accept_date IS NULL)) OR
           ((ll.price_override <> lla.price_override) OR
            (ll.price_override IS NULL AND lla.price_override IS NOT NULL) OR
            (ll.price_override IS NOT NULL AND lla.price_override IS NULL)) OR
           ((ll.tax_code_id <> lla.tax_code_id) OR
            (ll.tax_code_id IS NULL AND lla.tax_code_id IS NOT NULL) OR
            (ll.tax_code_id IS NOT NULL AND lla.tax_code_id IS NULL)) OR
           ((ll.shipment_num <> lla.shipment_num) OR
            (ll.shipment_num IS NULL AND lla.shipment_num IS NOT NULL) OR
            (ll.shipment_num IS NOT NULL AND lla.shipment_num IS NULL)) OR
           ((ll.sales_order_update_date <> lla.sales_order_update_date) OR
            (ll.sales_order_update_date IS NULL AND
             lla.sales_order_update_date IS NOT NULL) OR
            (ll.sales_order_update_date IS NOT NULL AND
             lla.sales_order_update_date IS NULL)) OR
           ((ll.cancel_flag <> lla.cancel_flag) OR
            (ll.cancel_flag IS NULL AND lla.cancel_flag IS NOT NULL) OR
            (ll.cancel_flag IS NOT NULL AND lla.cancel_flag IS NULL)) OR
           ((ll.start_date <> lla.start_date) OR
            (ll.start_date is null AND lla.start_date is not null) OR
            (ll.start_date is not null AND lla.start_date is null)) OR
           ((ll.end_date <> lla.end_date) OR
            (ll.end_date is null AND lla.end_date is not null) OR
            (ll.end_date is not null AND lla.end_date is null)))
    AND   r.org_id = ##$$ORGID$$##
    AND   ll.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Line Locations Archive',
    'RS',
    'There are data discrepancies between PO_LINE_LOCATIONS_ALL and
     PO_LINE_LOCATIONS_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  ------------------------------------------------
  -- Recent Document Data Integrity REL 3 (MGD2-7)
  ------------------------------------------------
  add_signature(
   'DATA_RANGE_REL3',
   'SELECT r.po_release_id,
           r.release_type type_lookup_code,
           d.po_header_id,
           d.po_line_id,
           d.line_location_id,
           d.po_distribution_id,
           r.revision_num,
           d.creation_date,
           d.last_update_date
    FROM po_distributions_all d,
         po_distributions_archive_all da,
         po_releases_all r,
         po_releases_archive_all ra,
         po_document_types_all dt
    WHERE r.po_release_id=d.po_release_id
    AND   r.po_header_id = ra.po_header_id
    AND   ra.latest_external_flag = ''Y''
    AND   r.authorization_status=''APPROVED''
    AND   nvl(r.closed_code,''OPEN'') not in (''FINALLY CLOSED'')
    AND   r.org_id = dt.org_id
    AND   r.release_type=dt.document_subtype
    AND   dt.document_type_code in (''RELEASE'')
    AND   r.revision_num=ra.revision_num
    AND   nvl(r.cancel_flag,''N'') <> ''Y''
    AND   d.po_distribution_id = da.po_distribution_id
    AND   da.latest_external_flag  = ''Y''
    AND   (((d.quantity_ordered <> da.quantity_ordered) OR
            (d.quantity_ordered IS NULL AND da.quantity_ordered IS NOT NULL) OR
            (d.quantity_ordered IS NOT NULL AND da.quantity_ordered IS NULL)) OR
           ((d.amount_ordered <> da.amount_ordered) OR
            (d.amount_ordered IS NULL AND da.amount_ordered IS NOT NULL) OR
            (d.amount_ordered IS NOT NULL AND da.amount_ordered IS NULL)) OR
           ((d.deliver_to_person_id <> da.deliver_to_person_id) OR
            (d.deliver_to_person_id IS NULL AND
             da.deliver_to_person_id IS NOT NULL) OR
            (d.deliver_to_person_id IS NOT NULL AND
             da.deliver_to_person_id IS NULL)) OR
           ((d.recovery_rate <> da.recovery_rate) OR
            (d.recovery_rate IS NULL AND da.recovery_rate IS NOT NULL) OR
            (d.recovery_rate IS NOT NULL AND da.recovery_rate IS NULL)))
    AND   r.org_id = ##$$ORGID$$##
    AND   r.creation_date >= to_date(''##$$FDATE$$##'')',
    'Synchronization Issues with Distributions Archive',
    'RS',
    'There are data discrepancies between PO_DISTRIBUTIONS_ALL and
     PO_DISTRIBUTIONS_ARCHIVE_ALL for this release, which can result
     in issues when trying cancel the document.',
    'Follow the solution instructions provided in [315607.1]',
    null,
    'FAILURE',
    'E',
    'RS');

  ----------------------------------------------
  -- Recent Document Data Integrity REL 4 (MGD5)
  ----------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '465068.1';
  add_signature(
   'DATA_RANGE_REL4',
   'SELECT h.org_id,
           h.po_header_id,
           h.segment1 po_number,
           ''Blanket Release'',
           r.release_num,
           r.po_release_id
    FROM po_releases_all r,
         po_headers_all h
    WHERE r.org_id = ##$$ORGID$$##
    AND   r.creation_date >= to_date(''##$$FDATE$$##'')
    AND   r.po_header_id = h.po_header_id
    AND   EXISTS (
            SELECT ll.po_release_id
            FROM po_line_locations_all ll,
                 po_system_parameters_all sp
            WHERE ll.po_release_id = r.po_release_id
            AND   ll.shipment_type in (''STANDARD'',''BLANKET'')
            AND   ll.po_release_id is not null
            AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                   (1 - nvl(ll.receive_close_tolerance,
                      nvl(sp.receive_close_tolerance,0))/100)) -
                   decode(sp.receive_close_code,
                     ''ACCEPTED'', nvl(ll.quantity_accepted,0),
                     ''DELIVERED'', (
                        SELECT sum(nvl(POD1.quantity_delivered,0))
                        FROM po_distributions_all pod1
                        WHERE pod1.line_location_id= ll.line_location_id),
                     nvl(ll.quantity_received,0)) <= 0.000000000000001
            AND   ((ll.quantity - nvl(ll.quantity_cancelled,0)) *
                   (1 - nvl(ll.invoice_close_tolerance,
                      nvl(sp.invoice_close_tolerance,0))/100)) -
                   nvl(ll.quantity_billed,0) <= 0.000000000000001
            AND   nvl(ll.closed_code,''OPEN'') IN (
                    ''OPEN'',''CLOSED FOR RECEIVING'',''CLOSED FOR INVOICE''))
    ORDER BY h.org_id, h.po_header_id, h.segment1, r.release_num',
    'PO Release Shipments Eligible to be Closed',
    'RS',
    'These blanket releases have shipments which are not closed but which are
     fully received and billed.',
    'Follow the solution instructions provided in [465068.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 1 (MGD3)
  -------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '427917.1';
  l_info('Script Name') := 'poarsynf.sql';
  add_signature(
   'DATA_RANGE_POREL1',
   'SELECT poh.segment1,
           poll.po_header_id,
           poll.po_line_id,
           poll.line_location_id,
           poll.po_release_id,
           pol.order_type_lookup_code,
           nvl(poll.quantity_billed,0) qtyamt_billed_on_po_line_loc,
           sum(nvl(pod.quantity_billed,0)) qtyamt_billed_on_po_dist
    FROM po_line_locations_all poll,
         po_distributions_all pod,
         po_lines_all pol,
         po_headers_all poh
    WHERE poll.line_location_id=pod.line_location_id
    AND   pol.po_line_id= pod.po_line_id
    AND   pol.po_header_id = poh.po_header_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''AMOUNT'',''QUANTITY'')
    AND   nvl(poll.cancel_flag,''N'') <> ''Y''
    AND   nvl(poll.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   poll.shipment_type IN (''STANDARD'',''BLANKET'',''PLANNED'',''SCHEDULED'')
    AND   poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    GROUP BY poh.segment1, poll.po_header_id, poll.po_line_id,
             poll.line_location_id, poll.po_release_id,
             pol.order_type_lookup_code, nvl(poll.quantity_billed,0)
    HAVING   round(nvl(poll.quantity_billed,0),15) <>
               round(sum(nvl(pod.quantity_billed,0)),15)
    UNION ALL
    SELECT poh.segment1,
           poll.po_header_id,
           poll.po_line_id,
           poll.line_location_id,
           poll.po_release_id,
           pol.order_type_lookup_code,
           nvl(poll.amount_billed,0) qtyamt_billed_on_po_line_loc,
           sum(nvl(pod.amount_billed,0)) qtyamt_billed_on_po_dist
    FROM po_line_locations_all poll,
         po_distributions_all pod,
         po_lines_all pol,
         po_headers_all poh
    WHERE poll.line_location_id=pod.line_location_id
    AND   pol.po_line_id= pod.po_line_id
    AND   pol.po_header_id = poh.po_header_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''FIXED PRICE'',''RATE'')
    AND   nvl(poll.cancel_flag,''N'') <> ''Y''
    AND   nvl(poll.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   poll.shipment_type in (''STANDARD'',''BLANKET'',''PLANNED'',''SCHEDULED'')
    AND   poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    GROUP BY poh.segment1, poll.po_header_id, poll.po_line_id,
             poll.line_location_id, poll.po_release_id,
             pol.order_type_lookup_code, nvl(poll.amount_billed,0)
    HAVING  round(nvl(poll.amount_billed,0),15) <>
              round(sum(nvl(pod.amount_billed,0)),15)',
    'Mismatched Quantity Billed',
    'RS',
    'These documents have a mismatch in the quantity billed between the shipments
     and the distributions.',
    'Follow the solution instructions provided in [427917.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 2 (MGD4)
  -------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '454060.1';
  add_signature(
   'DATA_RANGE_POREL2',
   'SELECT poh.segment1,
           pod.po_header_id,
           pod.po_line_id,
           pod.line_location_id,
           pod.po_release_id,
           pod.po_distribution_id,
           nvl(pod.quantity_billed,0) qtybilled_on_po_dist,
           nvl(pod.amount_billed,0) amtbilled_on_po_dist,
           sum(nvl(aid.quantity_invoiced,0)) qtyinvoiced_on_ap_dist,
           sum(nvl(aid.amount,0)) amtinvoiced_on_ap_dist,
           pol.order_type_lookup_code
    FROM po_distributions_all pod,
         ap_invoice_distributions_all aid,
         po_lines_all pol,
         po_headers_all poh
    WHERE pod.po_distribution_id=aid.po_distribution_id
    AND   pod.po_line_id = pol.po_line_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''AMOUNT'',''QUANTITY'')
    AND   aid.line_type_lookup_code in (''ITEM'',''PREPAY'',''ACCRUAL'')
    AND   poh.po_header_id = pol.po_header_id
    AND   poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    GROUP BY poh.segment1, pod.po_header_id, pod.po_line_id,
             pod.line_location_id, pod.po_release_id,
             pod.po_distribution_id, nvl(pod.quantity_billed,0),
             nvl(pod.amount_billed,0), pol.order_type_lookup_code
    HAVING (round(nvl(pod.quantity_billed,0),15) <>
             round(sum(nvl(aid.quantity_invoiced,0)),15) OR
            round(nvl(pod.amount_billed,0),15) <>
              round(sum(nvl(aid.amount,0)),15))
    UNION ALL
    SELECT poh.segment1,
           pod.po_header_id,
           pod.po_line_id,
           pod.line_location_id,
           pod.po_release_id,
           pod.po_distribution_id,
           nvl(pod.quantity_billed,0) qtybilled_on_po_dist,
           nvl(pod.amount_billed,0) amtbilled_on_po_dist,
           sum(nvl(aid.quantity_invoiced,0)) qtyinvoiced_on_ap_dist,
           sum(nvl(aid.amount,0)) amtinvoiced_on_ap_dist,
           pol.order_type_lookup_code
    FROM po_distributions_all pod,
         ap_invoice_distributions_all aid,
         po_lines_all pol,
         po_headers_all poh
    WHERE pod.po_distribution_id=aid.po_distribution_id
    AND   pod.po_line_id = pol.po_line_id
    AND   nvl(pol.order_type_lookup_code,''QUANTITY'') IN (''FIXED PRICE'',''RATE'')
    AND   aid.line_type_lookup_code in (''ITEM'',''PREPAY'',''ACCRUAL'')
    AND   poh.po_header_id = pol.po_header_id
    AND   poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    GROUP BY poh.segment1, pod.po_header_id, pod.po_line_id,
             pod.line_location_id, pod.po_release_id,
             pod.po_distribution_id, nvl(pod.quantity_billed,0),
             nvl(pod.amount_billed,0), pol.order_type_lookup_code
    HAVING round(nvl(pod.amount_billed,0),15) <>
             round(sum(nvl(aid.amount,0)),15)',
    'Mismatched Quantity or Amounts Billed',
    'RS',
    'These documents have a mismatch in the quantity or amount billed
     between the shipments or distributions and the values on the invoice
     distributions in Payables',
    'Follow the solution instructions provided in [454060.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  --------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 3 (MGD9)
  --------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1419114.1';
  add_signature(
   'DATA_RANGE_POREL3',
   'SELECT DISTINCT ph.po_header_id,
           ph.type_lookup_code,
           pl.po_line_id,
           pll.line_location_id,
           pl.unit_meas_lookup_code,
           pll.unit_meas_lookup_code
    FROM po_line_locations_all pll,
                 po_lines_all pl,
                 po_headers_all ph
    WHERE ph.org_id = ##$$ORGID$$##
    AND   ph.creation_date >= to_date(''##$$FDATE$$##'')
    AND   nvl(pll.unit_meas_lookup_code, -1) <>
            nvl(pl.unit_meas_lookup_code, -1)
    AND   pll.po_line_id = pl.po_line_id
    AND   pl.po_header_id = ph.po_header_id
    AND   pll.unit_meas_lookup_code IS NOT NULL
    AND   pl.unit_meas_lookup_code IS NOT NULL
    AND   nvl(pll.closed_code, ''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(pll.cancel_flag, ''N'') <> ''Y''
    AND   ((ph.type_lookup_code = ''BLANKET'' AND
            pll.po_release_id IS NOT NULL) OR
           ph.type_lookup_code <> ''BLANKET'')',
    'Unit of Measure (UOM) Mismatch',
    'RS',
    'These POs have a mismatch in the unit of measures assigned to the
     the shipments and the lines.',
    'Follow the solution instructions provided in [1419114.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ---------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 4 (MGD10)
  ---------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1379274.1';
  l_info('Bug Number') := '14782923';
  l_info('Script Name') := 'poxpoaprvl.sql';
  add_signature(
   'DATA_RANGE_POREL4',
   'SELECT h.segment1 po_number,
           h.po_header_id,
           h.org_id,
           h.cancel_flag,
           h.authorization_status
    FROM po_headers_all h
    WHERE h.org_id = ##$$ORGID$$##
    AND   h.creation_date >= to_date(''##$$FDATE$$##'')
    AND   nvl(cancel_flag, ''N'') = ''Y''
    AND   authorization_status = ''REQUIRES REAPPROVAL''',
    'Canceled PO in Requires Reapproval Status',
    'RS',
    'These purchase orders are canceled but the authorization status is
     ''Requires Reapproval''',
    'Follow the solution instructions provided in [1379274.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ---------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 5 (MGD11)
  ---------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1346647.1';
  l_info('Script Name') := 'tax_code_detect.sql';
  add_signature(
    'DATA_RANGE_POREL5',
   'SELECT ph.po_header_id,
           ph.segment1 po_number,
           pl.line_num,
           pll.line_location_id,
           pll.shipment_num,
           pll.tax_attribute_update_code,
           ''UPDATE'' "Correct Code"
    FROM po_headers_all ph,
         po_lines_all pl,
         po_line_locations_all pll
    WHERE ph.org_id = ##$$ORGID$$##
    AND   ph.creation_date >= to_date(''##$$FDATE$$##'')
    AND   ph.po_header_id = pll.po_header_id
    AND   pl.po_line_id = pll.po_line_id
    AND   nvl(pll.tax_attribute_update_code,''UPDATE'') <> ''UPDATE''
    AND   EXISTS (
            SELECT 1 FROM zx_lines_det_factors
            WHERE application_id = 201
            AND   entity_code = ''PURCHASE_ORDER''
            AND   trx_id = pll.po_header_id
            AND   trx_line_id = pll.line_location_id)',
    'Incorrect Tax Attribute Update Code - Approval Error',
    'RS',
    'These purchase orders have an incorrect value for tax attribute update code.
     This can cause the error Tax exception 023 (ORA-00001: unique constraint
     (ZX.ZX_LINES_DET_FACTORS_U1) violated) when approving.',
    'To correct this data corruption please create a Service Request with
     Oracle Support referencing [1346647.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ---------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 6 (MGD12)
  ---------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1269228.1';
  l_info('Script name') := 'poxaustat.sql';
  add_signature(
    'DATA_RANGE_POREL6',
   'SELECT ph.po_header_id,
           ph.segment1 po_number,
           ph.authorization_status
    FROM po_headers_all ph
    WHERE ph.org_id = ##$$ORGID$$##
    AND   ph.creation_date >= to_date(''##$$FDATE$$##'')
    AND   authorization_status = ''REQUIRES_REAPPROVAL''',
    'Invalid Authorization Status',
    'RS',
    'These purchase orders have an invalid value for authorization status
     (REQUIRES_REAPPROVAL instead of REQUIRES REAPPROVAL).
     This can result in errors such as the follwing when working in
     the Buyer Work Center and searching agreements for a supplier:<br/>
     <blockquote>Exception Details.<br/>
      oracle.apps.fnd.framework.OAException:
      java.lang.Exception: Assertion failure: The value cannot be null.<br/>
      at oracle.apps.fnd.framework.OAException.wrapperException(OAException.java:896)<br/>
      ...</blockquote>',
    'To correct this data please create a Service Request with Oracle
     Support referencing [1269228.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ---------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 7 (MGD13)
  ---------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '756627.1';
  add_signature(
    'DATA_RANGE_POREL7',
   'SELECT DISTINCT
           h.segment1 "PO_Number",
           h.po_header_id,
           d.rate "PO Dist Rate",
           h.currency_code "PO Currency Code",
           rl.rate "Req Line Rate",
           rl.currency_code "Req Line Currency",
           d.creation_date "PO Dist Creation Date",
           (d.rate/rl.rate) rate_ratio
    FROM po_distributions_all d,
         po_req_distributions_all rd,
         po_requisition_lines_all rl,
         po_headers_all h
    WHERE h.org_id = ##$$ORGID$$##
    AND   h.creation_date >= to_date(''##$$FDATE$$##'')
    AND   d.req_distribution_id = rd.distribution_id
    AND   rl.requisition_line_id = rd.requisition_line_id
    AND   rl.rate / d.rate < 0.5
    AND   h.po_header_id = d.po_header_id
    AND   h.currency_code = rl.currency_code
    ORDER BY rl.currency_code',
    'Incorrect Rate on Autocreated PO',
    'RS',
    'Foreign currency autocreated PO''s using the "Specify" option can result in
     the inverse rate being assigned.  This PO has an incorrect rate assigned.',
    'Please review [756627.1]. To correct the data please create a Service
     Request with Oracle Support referencing [756627.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  ---------------------------------------------------
  -- Recent Document Data Integrity  PO/REL 8 (MGD14)
  ---------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1280061.1';
  add_signature(
    'DATA_RANGE_POREL8',
   'SELECT pod.po_header_id,
           poh.segment1 po_number,
           poll.line_location_id,
           poll.ship_to_organization_id,
           pod.po_distribution_id,
           pod.destination_organization_id,
           null supply_source_id,
           null to_organization_id
    FROM po_distributions_all pod,
         po_line_locations_all poll,
         po_headers_all poh
    WHERE poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    AND   poh.po_header_id = poll.po_header_id
    AND   pod.line_location_id = poll.line_location_id
    AND   pod.po_header_id = poll.po_header_id
    AND   pod.destination_organization_id != poll.ship_to_organization_id
    AND   nvl(poll.closed_code,''OPEN'') != ''FINALLY CLOSED''
    AND   nvl(poll.cancel_flag,''N'') != ''Y''
    UNION
    SELECT poh.po_header_id,
           poh.segment1,
           poll.line_location_id,
           poll.ship_to_organization_id,
           null,
           null,
           mtl.supply_source_id,
           mtl.to_organization_id
    FROM mtl_supply mtl,
         po_line_locations_all poll,
         po_headers_all poh
    WHERE poh.org_id = ##$$ORGID$$##
    AND   poh.creation_date >= to_date(''##$$FDATE$$##'')
    AND   mtl.supply_type_code = ''PO''
    AND   mtl.po_line_location_id = poll.line_location_id
    AND   mtl.po_header_id = poll.po_header_id
    AND   mtl.to_organization_id != poll.ship_to_organization_id
    AND   nvl(poll.closed_code,''OPEN'') != ''FINALLY CLOSED''
    AND   nvl(poll.cancel_flag,''N'') != ''Y''
    AND   poh.po_header_id = poll.po_header_id',
    'Ship To Organization Mismatch',
    'RS',
    'The ship to organization on the PO does not match the deliver to organization
     on the distributions or in mtl_supply. This can cause approved PO''s
     not to be displayed in Inventory''s Supply/Demand Detail window.',
    'Please review [1280061.1]. To correct the data please create a Service
     Request with Oracle Support referencing [1280061.1] to obtain a fix.',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -----------------------------------------------
  -- Recent Document Data Integrity  REQ 1 (MGD6)
  -----------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '415151.1';
  l_info('Script Name') := 'poxrqesf.sql';
  add_signature(
   'DATA_RANGE_REQ1',
   'SELECT prl.requisition_header_id,
           prl.requisition_line_id,
           pll.line_location_id,
           prl.modified_by_agent_flag,
           prl.cancel_flag,
           prl.source_type_code
    FROM po_requisition_lines_all prl,
         po_line_locations_all pll
    WHERE prl.org_id = ##$$ORGID$$##
    AND   prl.creation_date >= to_date(''##$$FDATE$$##'')
    AND   prl.line_location_id = pll.line_location_id
    AND   pll.approved_flag = ''Y''
    AND   nvl(prl.cancel_flag,''N'') = ''N''
    AND   nvl(prl.modified_by_agent_flag,''N'') = ''N''
    AND   EXISTS (
            SELECT 1 FROM mtl_supply
            WHERE prl.requisition_line_id = supply_source_id
            AND   supply_type_code = ''REQ'')
    UNION ALL
    SELECT prl.requisition_header_id,
           prl.requisition_line_id,
           to_number(NULL) line_location_id,
           prl.modified_by_agent_flag,
           prl.cancel_flag,
           prl.source_type_code
    FROM po_requisition_lines_all prl
    WHERE prl.org_id = ##$$ORGID$$##
    AND   prl.creation_date >= to_date(''##$$FDATE$$##'')
    AND   (nvl(prl.cancel_flag,''N'') = ''Y'' OR
           (prl.cancel_flag = ''N'' AND
            prl.modified_by_agent_flag = ''Y''))
    AND   EXISTS (
              SELECT 1 FROM mtl_supply
              WHERE prl.requisition_line_id = supply_source_id
              AND   supply_type_code = ''REQ'')
    UNION ALL
    SELECT req_header_id,
           req_line_id,
           NULL,
           NULL,
           NULL,
           NULL
    FROM mtl_supply ms
    WHERE ms.supply_type_code = ''REQ''
    AND   ms.supply_source_id NOT IN (
            SELECT prl.requisition_line_id
            FROM po_requisition_lines_all prl)
    AND   ms.creation_date  >= to_date(''##$$FDATE$$##'')',
    'Invalid Supply/Demand for Requisition Lines',
    'RS',
    'These documents have canceled or modified or missing
     requisition lines with invalid supply existing in the
     mtl_supply table.',
    'Follow the solution instructions provided in [415151.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -----------------------------------------------
  -- Recent Document Data Integrity  REQ 2 (MGD7)
  -----------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1220964.1';
  l_info('Script Name') := 'POXIREQF.sql';
  add_signature(
   'DATA_RANGE_REQ2',
    'SELECT prl.requisition_header_id,
            prl.requisition_line_id,
            to_number(NULL) line_location_id,
            nvl(prl.quantity_delivered, 0),
            prl.quantity
     FROM mtl_supply ms,
          po_requisition_lines_all prl
     WHERE prl.org_id = ##$$ORGID$$##
     AND   prl.creation_date >= to_date(''##$$FDATE$$##'')
     AND   ms.supply_type_code = ''REQ''
     AND   prl.source_type_code=''INVENTORY''
     AND   prl.requisition_line_id = ms.supply_source_id
     AND   nvl(prl.quantity_delivered,0) >= prl.quantity',
    'Fully Received Lines Showing Pending Supply',
    'RS',
    'This requisition has fully received lines which continue to show
     pending supply.',
    'Follow the solution instructions provided in [1220964.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  -----------------------------------------------
  -- Recent Document Data Integrity  REQ 3 (MGD8)
  -----------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1432915.1';
  l_info('Script Name') := 'return_req_pool.sql';
  add_signature(
   'DATA_RANGE_REQ3',
   'SELECT rh.requisition_header_id req_header_id,
           rh.segment1 req_number,
           rl.requisition_line_id req_line_id,
           rl.line_num req_line_num,
           rl.line_location_id req_line_loc,
           rl.reqs_in_pool_flag req_pool_flag
    FROM po_requisition_headers_all rh,
         po_requisition_lines_all rl
    WHERE rh.org_id = ##$$ORGID$$##
    AND   rh.creation_date >= to_date(''##$$FDATE$$##'')
    AND   rh.requisition_header_id = rl.requisition_header_id
    AND   rh.authorization_status = ''APPROVED''
    AND   rl.reqs_in_pool_flag is null
    AND   rl.line_location_id is not null
    AND   nvl(rl.closed_code,''OPEN'') <> ''FINALLY CLOSED''
    AND   nvl(rl.cancel_flag,''N'') <> ''Y''
    AND   NOT EXISTS (
            SELECT 1 FROM po_line_locations_all ll
            WHERE ll.line_location_id = rl.line_location_id)',
    'Requisition lines not available in Autocreate form after PO deletion.',
    'RS',
    'This requisition has lines which are not available in the Autocreate
     form even after the associated purchase order has been deleted.',
    'Follow the solution instructions provided in [1432915.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info);

  /*###########################
    #  Document Type Setup    #
    ###########################*/

  l_info.delete;
  add_signature(
   'ORG_DOC_TYPES',
   'SELECT dt.type_name document_type,
           dt.org_id,
           dt.document_type_code,
           dt.document_subtype,
           dt.can_preparer_approve_flag "Preparer Can Approve",
           dt.can_change_approval_path_flag "Change Approval Path",
           dt.can_approver_modify_doc_flag "Approver Can Modify Doc",
           dt.can_change_forward_from_flag "Change Forward From",
           dt.can_change_forward_to_flag "Change Forward To",
           dt.forwarding_mode_code forwarding_method,
           s.name hierarchy_name,
           dt.default_approval_path_id,
           wfit.display_name workflow_process,
           wfrp.display_name workflow_top_process,
           dt.wf_createdoc_itemtype,
           dt.wf_createdoc_process,
           dt.ame_transaction_type,
           dt.archive_external_revision_code,
           dt.quotation_class_code,
           dt.security_level_code,
           dt.access_level_code,
           dt.disabled_flag,
           dt.use_contract_for_sourcing_flag,
           dt.include_noncatalog_flag,
           dt.document_template_code,
           dt.contract_template_code
    FROM po_document_types_all dt,
         per_position_structures s,
         wf_item_types_vl wfit,
         wf_runnable_processes_v wfrp
    WHERE dt.org_id = ##$$ORGID$$##
    AND   dt.default_approval_path_id = s.position_structure_id(+)
    AND   dt.wf_approval_itemtype = wfit.name(+)
    AND   dt.wf_approval_process = wfrp.process_name(+)
    AND   dt.document_type_code IN (''PO'',''PA'',
            ''REQUISITION'',''RELEASE'')',
    'Organization Document Types Setup',
    'NRS',
    null,
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');
    
  --------------------------------------------------------
  -- Data issues after upgrade (wf notifications stuck) --
  --------------------------------------------------------
  l_info.delete;
  l_info('Doc ID') := '1532406.1';
  add_signature(
   'UPGRADE_ALL',
   'SELECT  wiav.item_type,
            wiav.item_key,
            wiav.NAME,
            wiav.text_value
     FROM   wf_item_attribute_values wiav,
            WF_ITEM_ACTIVITY_STATUSES wias
     WHERE  wiav.NAME IN (''PO_REQ_APPROVE_MSG'',
                     ''PO_REQ_APPROVED_MSG'',
                     ''PO_REQ_NO_APPROVER_MSG'',
                     ''PO_REQ_REJECT_MSG'',
                     ''REQ_LINES_DETAILS'',
                     ''PO_LINES_DETAILS'')
            AND (wiav.text_value LIKE ''PLSQL:%POAPPRV%''
                  OR wiav.text_value LIKE ''PLSQL:%REQAPPRV%'')
            AND wiav.item_key = wias.item_key
            AND wiav.item_type = wias.item_type
            AND wias.notification_id IN (SELECT notification_id FROM wf_notifications
                                        WHERE message_type IN (''POAPPRV'',''REQAPPRV'')
                                        AND status <> ''CLOSED'')
            AND wias.begin_date >= to_date(''##$$FDATE$$##'')',
    'Documents with active revisions created before upgrade',
    'RS',
    'These documents have pending revisions that have been created and not closed before the upgrade.',
    'Follow the solution instructions provided in [1532406.1]',
    null,
    'FAILURE',
    'E',
    'RS',
    'Y',
    l_info,
    p_include_in_dx_summary => 'Y');    

  /*###########################
    #  AME Setup Information  #
    ###########################*/

  l_info.delete;
  add_signature(
   'AME_MANDATORY_ATTR',
  'SELECT atr.attribute_id,
          atr.name,
          atu.query_string,
          atr.description,
          atu.is_static
   FROM ame_attributes atr,
        ame_attribute_usages atu
   WHERE atr.attribute_id = atu.attribute_id
   AND   atu.application_id = ##$$AMEAPPID$$##
   AND   sysdate between atr.start_date AND
           nvl(atr.end_date - (1/86400),sysdate)
   AND   sysdate between atu.start_date AND
            nvl(atu.end_date - (1/86400),sysdate)
   AND   atr.attribute_id IN (
           SELECT attribute_id
           FROM ame_mandatory_attributes man
           WHERE man.action_type_id = -1
           AND   sysdate between man.start_date AND
                   nvl(man.end_date - (1/86400),sysdate))
   ORDER BY atr.name',
    'AME Mandatory Attributes',
    'NRS',
    'No mandatory attributes found',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');

  l_info.delete;
  add_signature(
   'AME_ITEM_CLASSES',
  'SELECT icu.item_class_order_number "Order Number",
          ic.name,
          ic.item_class_id,
          icu.item_id_query,
          decode(icu.item_class_par_mode,
            ''S'', ''Serial'' ,
            ''P'' ,''Parallel'',
            icu.item_class_par_mode) par_mode,
          decode(icu.item_class_sublist_mode,
            ''S'',''Serial'',
            ''P'',''Parallel'',
            ''R'',''pre-approvers first, then authority and post-approvers'',
            ''A'',''pre-approvers and authority approvers first, then post-approvers'',
            icu.item_class_sublist_mode) sublist_mode
   FROM ame_item_classes ic,
        ame_item_class_usages icu
   WHERE ic.item_class_id = icu.item_class_id
   AND   icu.application_id = ##$$AMEAPPID$$##
   AND   sysdate BETWEEN ic.start_date AND nvl(ic.end_date - (1/86400),sysdate)
   AND   sysdate BETWEEN icu.start_date AND nvl(icu.end_date - (1/86400),sysdate)
   ORDER BY icu.item_class_order_number',
    'AME Item Classes',
    'NRS',
    'No item classes found for this this transaction type',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'Y');

  l_info.delete;
  add_signature(
   'AME_IC_ATTR',
  'SELECT ic.name "Item Class",
          a.attribute_id,
          a.name,
          a.attribute_type,
          au.query_string,
          a.description,
          au.is_static
   FROM ame_attributes a,
        ame_attribute_usages au,
        ame_item_classes ic
   WHERE a.attribute_id = au.attribute_id
   AND   au.application_id = ##$$AMEAPPID$$##
   AND   a.item_class_id = ic.item_class_id
   AND   sysdate BETWEEN ic.start_date AND nvl(ic.end_date - (1/86400),sysdate)
   AND   sysdate BETWEEN a.start_date AND nvl(a.end_date - (1/86400),sysdate)
   AND   sysdate BETWEEN au.start_date AND nvl(au.end_date - (1/86400),sysdate)
   AND   a.attribute_id NOT IN (
           SELECT attribute_id
           FROM ame_mandatory_attributes ma
           WHERE ma.action_type_id = -1
           AND   sysdate BETWEEN ma.start_date AND
                   nvl(ma.end_date - (1/86400),sysdate))
   ORDER BY decode(ic.name,''header'',1,''line item'',2,''distribution'',3,4),
            a.name',
    'AME Item Class Attributes',
    'NRS',
    'No attributes these item classes',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'Y');

  l_info.delete;
  add_signature(
   'AME_RULES',
   'SELECT ic.name item_class,
           ic.name "##$$FK2$$##",
           decode(r.rule_type,
             1, ''Combination'',
             2, ''List Creation'',
             3, ''List Creation Exception'',
             4, ''List Modification'',
             5, ''Substitution'',
             6, ''Pre-list'',
             7, ''Post-list'',
             8, ''Production'',
             r.rule_type) "Rule Type",
           r.rule_id, r.rule_id "##$$FK1$$##",
           r.description,
           r.rule_key,
           r.start_date,
           r.end_date,
           nvl(to_char(ru.priority),''Disabled'') "priority",
           decode(ru.approver_category,
             ''A'', ''Action'',
             ''F'', ''FYI'',
             ru.approver_category) "Approver Category"
    FROM ame_rules r,
         ame_rule_usages ru,
         (
           SELECT ic.name, ic.item_class_id,
                  icu.item_class_order_number, icu.item_class_id item_clsid
            FROM ame_item_classes ic,
                 ame_item_class_usages icu                 
            WHERE ic.item_class_id = icu.item_class_id
            AND   icu.application_id = ##$$AMEAPPID$$##
            AND   sysdate BETWEEN ic.start_date AND
                    nvl(ic.end_date - (1/86400),sysdate)
            AND   sysdate BETWEEN icu.start_date AND
                    nvl(icu.end_date - (1/86400),sysdate)
         ) ic
    WHERE r.rule_type BETWEEN 1 and 8
    AND   ic.item_class_id (+) = r.item_class_id
    AND   (r.rule_type IN (3, 4) OR
           ic.item_class_id is not null)
    AND   r.rule_id = ru.rule_id
    AND   ru.item_id = ##$$AMEAPPID$$##
    AND   (sysdate between r.start_date AND nvl(r.end_date - (1/86400),sysdate) OR
           (r.start_date > sysdate AND
             (r.end_date is null OR r.end_date > r.start_date)))
    AND   (sysdate between ru.start_date AND nvl(ru.end_date - (1/86400),sysdate) OR
           (ru.start_date > sysdate AND
             (ru.end_date is null OR ru.end_date > ru.start_date)))
    ORDER BY ic.item_class_order_number,
    item_clsid,
    r.rule_type, 
    r.rule_id',
    'AME Rules',
    'NRS',
    'No Rules found.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N',
    l_info,
    VARCHAR_TBL('AME_RULE_CONDITIONS','AME_RULE_ACTIONS','AME_LINE_RULE'));

  l_info.delete;
  add_signature(
   'AME_RULE_CONDITIONS',
   'SELECT c.condition_id,
           decode(c.condition_type,
             ''auth'','' '',
             ''pre'', ''Exception : '',
             ''post'', ''List-Modification : '') "Condition Type",
             ame_condition_pkg.getDescription(c.condition_id) Description
    FROM ame_condition_usages cu,
         ame_conditions c
    WHERE cu.rule_id = ##$$FK1$$##
    AND   c.condition_id = cu.condition_id
    AND   sysdate between c.start_date AND nvl(c.end_date - (1/86400),sysdate)
    AND   (sysdate between cu.start_date AND nvl(cu.end_date - (1/86400),sysdate) OR
           (cu.start_date > sysdate AND
            (cu.end_date is null OR cu.end_date > cu.start_date)))',
    'AME Rule Conditions',
    'NRS',
    'No Rules Conditions found.',
    null,
    null,
    'SUCCESS',
    'I',
    'RS',
    'N');

  l_info.delete;
  add_signature(
   'AME_RULE_ACTIONS',
   'SELECT a.action_id,
           ame_action_pkg.getDescription(a.action_id) "Description"
    FROM ame_action_usages au,
         ame_actions a
    WHERE au.rule_id = ##$$FK1$$##
    AND   a.action_id = au.action_id
    AND   sysdate between a.start_date AND nvl(a.end_date - (1/86400),sysdate)
    AND   (sysdate between au.start_date AND nvl(au.end_date - (1/86400),sysdate) OR
           (au.start_date > sysdate AND
            (au.end_date is null OR au.end_date > au.start_date)))',
    'AME Rule Actions',
    'NRS',
    'No Rules Actions found.',
    null,
    null,
    'SUCCESS',
    'I',
    'RS',
    'N');

    
  l_info.delete;
  add_signature(
   'AME_LINE_RULE',
   'SELECT ''Line Item Rule detected!''
    FROM dual
    WHERE lower(''##$$FK2$$##'') = ''line item'' ',
    'AME Line Item Rule',
    'RS',
    'Line Item Rule detected!',
    'Oracle Purchasing does not support Line Item level approvals in AME. Please review the above rule and move the condition at Header level.',
    null,
    'FAILURE',
    'E',
    'N',
    'N');    
    
    
-- 5 to go in here

  l_info.delete;
  add_signature(
   'AME_ACTION_TYPES',
   'SELECT atc.order_number,
           at.name,
           at.action_type_id, at.action_type_id "##$$FK1$$##",
           decode(atc.voting_regime,
             ''S'', ''Serial'',
             ''C'', ''Consensus'',
             ''F'', ''First Responder Wins'',
             atc.voting_regime) "Voting Regime",
           decode(atc.chain_ordering_mode,
             ''S'', ''Serial'',
             ''P'', ''Parallel'',
             atc.chain_ordering_mode) "Chain Order Mode",
           decode(atu.rule_type,2,1,atu.rule_type)
    FROM ame_action_type_config atc,
         ame_action_types at,
         ame_action_type_usages atu
    WHERE atc.application_id = ##$$AMEAPPID$$##
    AND   at.action_type_id = atc.action_type_id
    AND   at.action_type_id = atu.action_type_id
    AND   sysdate between at.start_date and nvl(at.end_date - (1/86400),sysdate)
    AND   sysdate between atu.start_date and nvl(atu.end_date - (1/86400),sysdate)
    AND   sysdate between atc.start_date and nvl(atc.end_date - (1/86400),sysdate)
    ORDER BY atu.rule_type,atc.order_number
    ',
    'AME Action Types',
    'NRS',
    'No Action Types found.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N',
    l_info,
    VARCHAR_TBL('AME_ACTION_TP_REQ_ATTR','AME_ACTION_TP_ACTIONS'));

  l_info.delete;
  add_signature(
   'AME_ACTION_TP_REQ_ATTR',
   'SELECT atr.name,
           atr.attribute_type
    FROM ame_attributes atr
    WHERE sysdate BETWEEN atr.start_date AND nvl(atr.end_date - (1/86400),sysdate)
    AND   atr.attribute_id IN (
            SELECT attribute_id FROM ame_mandatory_attributes ma
            WHERE ma.action_type_id = ##$$FK1$$##
            AND   sysdate BETWEEN ma.start_date AND
                    nvl(ma.end_date - (1/86400),sysdate))',
    'AME Action Type Required Attributes',
    'NRS',
    'No Required Attributes found.',
    null,
    null,
    'SUCCESS',
    'I',
    'RS',
    'N');

  l_info.delete;
  add_signature(
    'AME_ACTION_TP_ACTIONS',
    'SELECT act.action_id,
           act.parameter,
           act.parameter_two,
           act.description
    FROM ame_actions act
    WHERE act.action_type_id = ##$$FK1$$##
    AND   sysdate BETWEEN act.start_date AND nvl(act.end_date - (1/86400),sysdate)
    AND   act.created_by NOT IN (1,120)',
    'AME Action Type Actions',
    'NRS',
    'No Actions found.',
    null,
    null,
    'SUCCESS',
    'I',
    'RS',
    'N');

  l_info.delete;
  add_signature(
   'AME_APPR_GROUPS',
   'SELECT agf.order_number,
           agr.approval_group_id, agr.approval_group_id "##$$FK1$$##",
           agr.name,
           decode(agf.voting_regime,
             ''S'',''Serial'',
             ''C'', ''Consensus'',
             ''F'', ''First Responder Wins'',
             ''O'', ''Order Number'',
             agf.voting_regime) "Voting Regime",
           agr.description,
           agr.query_string,
           agr.is_static
    FROM ame_approval_group_config agf,
         ame_approval_groups agr
    WHERE agf.application_id = ##$$AMEAPPID$$##
    AND   agr.approval_group_id = agf.approval_group_id
    AND   sysdate BETWEEN agr.start_date AND nvl(agr.end_date - (1/86400),sysdate)
    AND   sysdate BETWEEN agf.start_date AND nvl(agf.end_date - (1/86400),sysdate)
    ORDER BY agf.order_number, agr.approval_group_id',
    'AME Approval Groups',
    'NRS',
    'No approval groups found.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'Y',
    l_info,
    VARCHAR_TBL('AME_APPR_GROUP_ITEMS'));

  l_info.delete;
  add_signature(
   'AME_APPR_GROUP_ITEMS',
   'SELECT agi.order_number,
           agi.approval_group_item_id "Item ID",
           decode(agi.parameter_name,
             ''OAM_group_id'', ''AME Group'',
             ''wf_roles_name'', ''WF Role'',
             agi.parameter_name) "Parameter Name",
           agi.parameter
    FROM ame_approval_group_items agi
    WHERE agi.approval_group_id = ##$$FK1$$##
    AND   sysdate BETWEEN agi.start_date AND nvl(agi.end_date - (1/86400),sysdate)
    ORDER BY agi.order_number',
    'Approval Group Items',
    'NRS',
    'No items found for this approval group.',
    null,
    null,
    'ALWAYS',
    'I',
    'RS');

   

  l_info.delete;
  add_signature(
   'AME_CONFIG_VARS',
  'SELECT cfg.variable_name,
          cfg.variable_value
   FROM ame_config_vars cfg
   WHERE cfg.application_id IN (0, ##$$AMEAPPID$$##)
   AND   sysdate BETWEEN cfg.start_date AND
           nvl(cfg.end_date - (1/86400),sysdate)
   ORDER BY cfg.variable_name',
    'AME Configuration Variables',
    'NRS',
    'No configuration variables found',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'Y');
    
  l_info.delete;
  add_signature(
   'PROC_CODE_LEVEL_12_0',
   'SELECT distinct(bug_number), decode((bug_number),
      ''4440000'',''Release 12.0.0 - provides R12 baseline code for PRC_PF'',
      ''5082400'',''Release 12.0.1'',
      ''5484000'',''Release 12.0.2 - provides R12.PRC_PF.A.delta.2'',
      ''6141000'',''Release 12.0.3 - provides R12.PRC_PF.A.delta.3'',
      ''6435000'',''Release 12.0.4 - provides R12.PRC_PF.A.delta.4'',
      ''6728000'',''Release 12.0.6 - provides R12.PRC_PF.A.delta.6'',
      ''7015582'',''Procurement Release 12.0 Rollup Patch 5'',
      ''7218243'',''Procurement R12.0 Update July 2008'',
      ''7291462'',''Procurement R12.0 Update August 2008'',
      ''7355145'',''Procurement R12.0 Update Sept 2008'',
      ''7433336'',''Procurement R12.0 Update Oct 2008'',
      ''7505241'',''Procurement R12.0 Update Nov 2008'',
      ''7600636'',''Procurement R12.0 Update Dec 2008'',
      ''7691702'',''Procurement R12.0 Update Jan 2009'',
      ''8298073'',''Procurement R12.0 Update Mar 2009'',
      ''8392570'',''Procurement R12.0 Update Apr 2009'',
      ''8474052'',''Procurement R12.0 Update May 2009'',
      ''8555479'',''Procurement R12.0 Update Jun 2009'',
      ''8658242'',''Procurement R12.0 Update Jul 2009'',
      ''8781255'',''Procurement R12.0 Update Aug 2009'',
      ''Other'') "Description"
    FROM ad_bugs
    WHERE bug_number IN
      (''4440000'',''5082400'',''5484000'',''6141000'',''6435000'',
       ''6728000'',''7015582'',''7218243'',''7291462'',''7355145'',
       ''7433336'',''7505241'',''7600636'',''7691702'',''8298073'',
       ''8392570'',''8474052'',''8555479'',''8658242'',''8781255'')
    ORDER BY 2',
    'Patches Applied',
    'NRS',
    'No patches applied',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N',
    p_include_in_dx_summary => 'Y');
    
  l_info.delete;
  add_signature(
   'PROC_CODE_LEVEL_12_1',
   'SELECT distinct(bug_number), decode((bug_number),
      ''7303030'',''Release 12.1.1 - provides R12.1 baseline code for PRC_PF'',
      ''7303033'',''Release 12.1.2 - provides R12.PRC_PF.B.delta.2'',
      ''9239090'',''Release 12.1.3 - provides R12.PRC_PF.B.delta.3'',
      ''8522002'',''R12.PRC_PF.B.delta.2'',
      ''9249354'',''R12.PRC_PF.B.delta.3'',
      ''10417963'',''Procurement R12.1.3 Update 2011/02 February 2011'',
      ''11817843'',''Procurement R12.1.3 Update 2011/04 April 2011'',
      ''12661793'',''Procurement R12.1.3 Update 2011/11 November 2011'',
      ''13984450'',''Procurement R12.1.3 Update 2012/06 June 2012'',
      ''14254641'',''Procurement R12.1.3 Update 2012/09 September 2012'',
      ''15843459'',''Procurement R12.1.3 Update 2013/03 March 2013'',
      ''17525552'',''Consolidated RUP covering iSupplier Portal Bug Fixes, Sourcing Bug Fixes post 12.1.3 and SLM new features'',
      ''17863140'',''Latest Recommended Patch Collection for Oracle Purchasing'',
      ''18120913'',''Procurement R12.1.3 Update 2014/01 January 2014'',
      ''17774755'',''Oracle E-Business Suite Release 12.1.3+ Recommended Patch Collection 1 [RPC1]'',
      ''18911810'',''Procurement R12.1.3 Update 2014/07 July 2014'',
      ''19030202'',''Oracle E-Business Suite Release 12.1.3+ Recommended Patch Collection 2 [RPC2]'',
      ''21198991'',''Procurement R12.1.3 Update 2015/03 March 2015'',
      ''Other'') "Description"
    FROM ad_bugs
    WHERE bug_number IN
      (''7303030'',''7303033'',''9239090'',''8522002'',''9249354'',
       ''10417963'',''11817843'',''12661793'',''13984450'',''14254641'',
       ''15843459'',''17525552'',''17863140'',''18120913'',''17774755'',
       ''18911810'',''19030202'',''21198991'')
    ORDER BY 2',
    'Patches Applied',
    'NRS',
    'No patches applied',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N',
    p_include_in_dx_summary => 'Y');

  l_info.delete;
  add_signature(
   'PROC_CODE_LEVEL_12_2',
   'SELECT distinct(bug_number), decode((bug_number),
      ''16910001'',''Release 12.2.2 - provides R12.2 baseline code for PRC_PF'',
      ''17036666'',''Release 12.2.3 - provides R12.PRC_PF.B.delta.3'',
      ''17947999'',''Release 12.2.3 - provides R12.PRC_PF.B.delta.4'',
      ''17919161'',''12.2.4 -ORACLE E-BUSINESS SUITE 12.2.4 RELEASE UPDATE PACK'',
      ''Other'') "Description"
    FROM ad_bugs
    WHERE bug_number IN
      (''16910001'',''17036666'',''17947999'',''17919161'')
    ORDER BY 2',
    'Patches Applied',
    'NRS',
    'No patches applied',
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');   
    
    
  l_info.delete;
  add_signature(
   'PO_CHANGE_ORDER_TOLERANCE',
   'select pco.change_order_type, pco.tolerance_name, nvl(to_char(pco.maximum_increment), ''NULL'') "Maximum Increment", pco.last_update_date, fu.user_name "Updated By"
      from po_change_order_tolerances_all pco,
           hr_operating_units ho,
           fnd_user fu
      where pco.org_id = ho.organization_id
      and pco.last_updated_by = fu.user_id
      and pco.org_id = ##$$ORGID$$##
      and change_order_type in  (''CO_ORDERS'', ''CO_AGREEMENTS'',''CO_RELEASES'')
      order by pco.change_order_type',
    'PO Change Order  Tolerance',
    'NRS',
    null,
    null,
    null,
    'ALWAYS',
    'I',
    'RS',
    'N');       
    

EXCEPTION WHEN OTHERS THEN
  print_log('Error in load_signatures');
  raise;
END load_signatures;

-----------------------------------------------
-- Diagnostic specific functions and procedures
-----------------------------------------------

-- Verify approver moved above run sql due to required kluge
-- since verify_authority API cannot be run from a query

FUNCTION get_result RETURN VARCHAR2 IS
BEGIN
  return(g_app_results('STATUS')||':'||
    nvl(g_app_results('CODE'),'NULL'));
END get_result;

FUNCTION get_fail_msg RETURN VARCHAR2 IS
BEGIN
  return(g_app_results('FAIL_MSG'));
END get_fail_msg;

FUNCTION get_exc_msg RETURN VARCHAR2 IS
BEGIN
  return(g_app_results('EXC_MSG'));
END get_exc_msg;

FUNCTION get_doc_amts(p_amt_type IN VARCHAR2)
  RETURN NUMBER IS
  l_currency      VARCHAR2(15);
  l_precision     NUMBER(1);
  l_ext_precision NUMBER(2);
  l_min_acct_unit NUMBER;
  l_net_total     NUMBER;
  l_doc_subtype   VARCHAR2(50);
  l_docid         NUMBER;
  l_code          VARCHAR2(1);
  l_tax           NUMBER;
  l_step          VARCHAR2(5);
BEGIN
  l_step := '10';

  l_doc_subtype := g_sql_tokens('##$$SUBTP$$##');
  l_docid := to_number(g_sql_tokens('##$$DOCID$$##'));

  IF NOT g_doc_amts.exists('NET_TOTAL') THEN
    -- Get currency
    IF g_sql_tokens('##$$TRXTP$$##') IN ('PO','PA','RELEASE') THEN
      l_step := '20';
      BEGIN
        SELECT currency_code INTO l_currency
        FROM po_headers_all 
        WHERE po_header_id = l_docid;
      EXCEPTION WHEN OTHERS THEN 
        l_currency := null;
      END;
    ELSIF g_sql_tokens('##$$TRXTP$$##') IN ('REQUISITION') THEN
      l_step := '30';
      BEGIN
        SELECT max(currency_code) INTO l_currency
        FROM po_requisition_lines_all 
        WHERE requisition_header_id = l_docid;
      EXCEPTION WHEN OTHERS THEN 
        l_currency := null;
      END;
    END IF;

    IF l_currency is null THEN
      l_currency := 'USD';
    END IF;

    l_step := '40';
    fnd_currency.get_info(l_currency, l_precision, l_ext_precision,
      l_min_acct_unit);

    g_doc_amts('PRECISION') := l_precision;
    g_doc_amts('EXT_PRECISION') := l_ext_precision;
    g_doc_amts('MIN_ACCT_UNIT') := l_min_acct_unit;

    -- Get net_total pull code from po_notifications_sv3.get_doc_total
    -- since that uses operating unit striped views
    l_step := '50';
    IF l_doc_subtype IN ('BLANKET', 'CONTRACT') THEN
      SELECT blanket_total_amount INTO l_net_total
      FROM po_headers_all ph
      WHERE ph.po_header_id = l_docid;
    ELSE
      IF (l_doc_subtype IN ('PLANNED', 'STANDARD')) THEN
        l_code := 'H';
      ELSIF (l_doc_subtype IN ('RELEASE', 'SCHEDULED')) THEN
        l_code := 'R';
      ELSIF (l_doc_subtype IN ('INTERNAL', 'PURCHASE')) THEN
        l_code := 'E';
      END IF;
      l_net_total := po_core_s.get_total(l_code, l_docid);
    END IF;

    g_doc_amts('NET_TOTAL') := l_net_total;

    IF g_sql_tokens('##$$TRXTP$$##') IN ('PO','PA') THEN
      l_step := '60';
      IF l_min_acct_unit > 0 THEN
        l_step := '70';
        SELECT nvl(sum(round(d.nonrecoverable_tax *
                 decode(nvl(d.quantity_ordered,0),
                   0, decode(nvl(d.amount_ordered,0),
                        0, 0,
                        (nvl(d.amount_ordered,0) - nvl(d.amount_cancelled,0)) /
                          d.amount_ordered),
                   (nvl(d.quantity_ordered,0) - nvl(d.quantity_cancelled,0)) /
                     d.quantity_ordered)
                 / l_min_acct_unit) * l_min_acct_unit), 0) tax
        INTO l_tax
        FROM po_distributions d
        WHERE po_header_id = to_number(g_sql_tokens('##$$DOCID$$##'));
      ELSE
        l_step := '80';
        SELECT nvl(sum(round(d.nonrecoverable_tax *
                 decode(nvl(d.quantity_ordered,0),
                   0, decode(nvl(d.amount_ordered,0),
                        0, 0,
                        (nvl(d.amount_ordered,0) - nvl(d.amount_cancelled,0)) /
                          d.amount_ordered),
                   (nvl(d.quantity_ordered,0) - nvl(d.quantity_cancelled,0)) /
                     d.quantity_ordered),
                 l_precision)), 0) tax
        INTO l_tax
        FROM po_distributions_all d
        WHERE po_header_id = to_number(g_sql_tokens('##$$DOCID$$##'));
      END IF;
    ELSIF g_sql_tokens('##$$TRXTP$$##') = 'RELEASE' THEN
      IF l_min_acct_unit > 0 THEN
        l_step := '90';
        SELECT nvl(sum(round(d.nonrecoverable_tax * 
                 decode(nvl(d.quantity_ordered,0),
                   0, decode(nvl(d.amount_ordered,0),
                        0, 0,
                        (nvl(d.amount_ordered,0) - nvl(d.amount_cancelled,0)) /
                          d.amount_ordered),
                   (nvl(d.quantity_ordered,0) - nvl(d.quantity_cancelled,0)) /
                     d.quantity_ordered) /
                    l_min_acct_unit) * l_min_acct_unit), 0) tax
        INTO l_tax
        FROM po_distributions_all d
        WHERE po_release_id =  to_number(g_sql_tokens('##$$RELID$$##'));
      ELSE
        l_step := '100';
        SELECT nvl(sum(round(d.nonrecoverable_tax *
                 decode(nvl(d.quantity_ordered,0),
                   0, decode(nvl(d.amount_ordered,0),
                        0, 0,
                        (nvl(d.amount_ordered,0) - nvl(d.amount_cancelled,0)) /
                          d.amount_ordered),
                   (nvl(d.quantity_ordered,0) - nvl(d.quantity_cancelled,0)) /
                     d.quantity_ordered),
                 l_precision)), 0) tax
      INTO l_tax
      FROM po_distributions_all d
      WHERE po_release_id = to_number(g_sql_tokens('##$$RELID$$##'));
     END IF;
    ELSIF g_sql_tokens('##$$TRXTP$$##') = 'REQUISITION' THEN
      l_step := '110';
      SELECT nvl(sum(nonrecoverable_tax), 0) tax
      INTO l_tax
      FROM po_requisition_lines_all rl,
           po_req_distributions_all rd
      WHERE rl.requisition_header_id = to_number(g_sql_tokens('##$$DOCID$$##'))
      AND   rd.requisition_line_id = rl.requisition_line_id
      AND   nvl(rl.cancel_flag,'N') = 'N'
      AND   nvl(rl.modified_by_agent_flag, 'N') = 'N' ;
    END IF;

    l_step := '120';
    g_doc_amts('TAX') := l_tax;
    g_doc_amts('TOTAL') := g_doc_amts('NET_TOTAL') + g_doc_amts('TAX');
  END IF;
  l_step := '130';
  RETURN(g_doc_amts(p_amt_type));

EXCEPTION WHEN OTHERS THEN
  print_log('Error in get_doc_amts:'||l_step||': '||sqlerrm);
  raise;
END get_doc_amts;

-----------------------------------------------------------
-- Function to check the version of a package body
-- against a specific provided version
-- Input params:
--    - package name
--    - version to compare against
-- return 1 if higher, 0 if the same, -1 if lower
-----------------------------------------------------------

FUNCTION chk_pkg_body_version(p_package_name IN VARCHAR2, p_expected_version IN VARCHAR2) 
   RETURN NUMBER IS

   l_step VARCHAR2(2);
   l_package_version VARCHAR2 (100);
   l_expected_version VARCHAR2 (100);
   l_pkg_ver_seg     NUMBER;
   l_expect_ver_seg  NUMBER;
   l_next_pos1 NUMBER;
   l_next_pos2 NUMBER;
   
   CURSOR c_package_version (p_package_name VARCHAR2) IS
     SELECT rtrim(ltrim(substr(ds.text, instr(ltrim(rtrim(ds.text)), ' 1', 1), (instr(ltrim(rtrim(ds.text)), ' 20') - instr(ltrim(rtrim(ds.text)), ' 1', 1))))) 
      FROM dba_source ds, dba_objects do
      WHERE upper(ds.name) = p_package_name
      AND ds.line = 2
      AND ds.name = do.object_name
      AND ds.type = do.object_type
      AND do.object_type = 'PACKAGE BODY';
   
BEGIN
   l_step := '10';
   l_expected_version := p_expected_version;
   
   OPEN c_package_version(p_package_name);
      FETCH c_package_version INTO l_package_version;
   CLOSE c_package_version;
      
   print_log('Comparing package ' || p_package_name || ' version ' || l_package_version || ' against ' || l_expected_version);

   l_step := '20';
   loop
      
      l_step := '30';
      l_next_pos1 := to_number(nvl(instr(l_package_version, '.'), 0));
      
      if (l_next_pos1 != 0) then 
         l_pkg_ver_seg := to_number(substr (l_package_version, 1, l_next_pos1));
         l_package_version := substr (l_package_version, l_next_pos1+1);
      else    
         l_pkg_ver_seg := l_package_version;
      end if;
      
      l_next_pos2 := to_number(nvl(instr(l_expected_version, '.'), 0));
      if (l_next_pos2 != 0) then 
         l_expect_ver_seg := to_number(substr (l_expected_version, 1, l_next_pos2));
         l_expected_version := substr(l_expected_version, l_next_pos2+1);
      else
          l_expect_ver_seg := l_expected_version;
      end if;    
          
      l_step := '40';
      if ((l_pkg_ver_seg > l_expect_ver_seg) or 
          ((l_pkg_ver_seg = l_expect_ver_seg) and (l_next_pos2 = 0) and (l_next_pos1 > 0))) then
          print_log ('Current version is greater.');
          return 1;
      elsif ((l_pkg_ver_seg < l_expect_ver_seg) or 
           ((l_pkg_ver_seg = l_expect_ver_seg) and (l_next_pos1 = 0) and (l_next_pos2 > 0))) then
          print_log ('Current version is lower.');
          return -1;
      end if;
      
     exit when ((l_pkg_ver_seg is null) or (l_expect_ver_seg is null) or (l_next_pos1 = 0) or (l_next_pos2 = 0));
   end loop;
   
   l_step := '50';
   print_log ('Versions are equal.');   
   RETURN 0;
   
EXCEPTION WHEN OTHERS THEN
  print_log('Error in chk_pkg_body_version:'||l_step||': '||sqlerrm);
  return -1;  
END chk_pkg_body_version;



---------------------------------
-- MAIN ENTRY POINT
---------------------------------


PROCEDURE main_single(
      p_org_id          IN NUMBER   DEFAULT null,
      p_trx_type        IN VARCHAR2 DEFAULT null,
      p_trx_num         IN VARCHAR2 DEFAULT null,
      p_release_num     IN NUMBER   DEFAULT null,
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y') IS
      
BEGIN

  main(
      p_mode   => 'SINGLE',
      p_org_id => p_org_id,
      p_trx_type => p_trx_type,
      p_trx_num => p_trx_num,
      p_release_num => p_release_num,
      p_include_wf => 'Y',
      p_from_date => p_from_date,
      p_max_output_rows => p_max_output_rows,
      p_debug_mode => p_debug_mode,
      p_calling_from => 'sql script');



END main_single;


PROCEDURE main_all(
      p_org_id          IN NUMBER   DEFAULT null,
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y') IS

BEGIN

  main(
      p_mode   => 'ALL',  
      p_org_id => p_org_id,
      p_trx_type => 'ANY',
      p_trx_num => null,
      p_release_num => null,
      p_include_wf => 'N',
      p_from_date => p_from_date,
      p_max_output_rows => p_max_output_rows,
      p_debug_mode => p_debug_mode,
      p_calling_from => 'sql script');

END main_all;



PROCEDURE main (
      p_mode            IN VARCHAR2 DEFAULT null,  
      p_org_id          IN NUMBER   DEFAULT null,
      p_trx_type        IN VARCHAR2 DEFAULT null,
      p_trx_num         IN VARCHAR2 DEFAULT null,
      p_release_num     IN NUMBER   DEFAULT null,
      p_include_wf      IN VARCHAR2 DEFAULT 'Y',
      p_from_date       IN DATE     DEFAULT sysdate - 90,
      p_max_output_rows IN NUMBER   DEFAULT 20,
      p_debug_mode      IN VARCHAR2 DEFAULT 'Y',
      p_calling_from    IN VARCHAR2 DEFAULT null) IS

  l_sql_result VARCHAR2(1);
  l_step       VARCHAR2(5);
  l_analyzer_end_time   TIMESTAMP;

BEGIN

  -- re-initialize values 
  g_sect_no := 1;
  g_sig_id := 0;
  g_item_id := 0;
  
  l_step := '10';
  initialize_files;
  -- set session language as US EN to avoid wfstat messages in other languages
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_LANGUAGE=''AMERICAN''';
  
  
  -- PSD #11
  -- Title of analyzer!! - do not add word 'analyzer' at the end as it is appended in code where title is called   
  analyzer_title := 'Procurement Approval';

  l_step := '20';
 -- PSD #12
  validate_parameters(
      p_mode,  
      p_org_id,
      p_trx_type,
      p_trx_num,
      p_release_num,
      p_include_wf,
      p_from_date,
      p_max_output_rows,
      p_debug_mode,
      p_calling_from);

      
  l_step := '30';
  print_rep_title(analyzer_title);

  l_step := '40';
  load_signatures;

  l_step := '50';
  print_toc('Sections In This Report');

  -- Start of Sections and signatures
  l_step := '60';
  print_out('<div id="tabCtrl">');

  IF p_trx_num is not null THEN
    l_step := '70';
    
    start_section('Single Document Details');
      set_item_result(run_stored_sig('DOC_DETAIL_DOC_TYPE'));
      IF p_trx_type IN ('PO','PA') THEN
        set_item_result(run_stored_sig('DOC_DETAIL_PO_HEADER'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_HEADER_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_LINES'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_LINES_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_LINE_LOCATIONS'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_LINE_LOCATIONS_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_DISTS'));
        set_item_result(run_stored_sig('DOC_DETAIL_PO_DISTS_ARCHIVE'));        
        set_item_result(run_stored_sig('Note390023.1_case_PO10'));
        -- signature is specific to R12.1 and R12.2
        IF ((substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') OR (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.2')) THEN   
           set_item_result(run_stored_sig('Note1565821.1'));
        END IF;   
      ELSIF p_trx_type = 'REQUISITION' THEN
        set_item_result(run_stored_sig('DOC_DETAIL_REQ_HEADER'));
        set_item_result(run_stored_sig('DOC_DETAIL_REQ_LINES'));
        set_item_result(run_stored_sig('DOC_DETAIL_REQ_DISTS'));
        set_item_result(run_stored_sig('Note390023.1_case_REQ9'));
      ELSIF p_trx_type = 'RELEASE' THEN
        set_item_result(run_stored_sig('DOC_DETAIL_REL_HEADER'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_HEADER_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_LINES'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_LINES_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_LINE_LOCATIONS'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_LINE_LOCATIONS_ARCHIVE'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_DISTS'));
        set_item_result(run_stored_sig('DOC_DETAIL_REL_DISTS_ARCHIVE'));
        set_item_result(run_stored_sig('Note390023.1_case_REL7'));
      END IF;
    end_section;

    
    --Verify if any open change requests exist for the current document   
    l_step := '74';   
    start_section('Change Requests');
        l_sql_result := run_stored_sig('DOC_DISPLAY_OPEN_CHG_REQUESTS');
        set_item_result(l_sql_result);
        set_item_result(run_stored_sig('PO_CHANGE_ORDER_TOLERANCE'));
        
        -- If an open change request is found, print the relevant Workflow information. Otherwise, skip this step
        IF (l_sql_result = 'W') THEN
            set_item_result(run_stored_sig('Workflow Processes Involved Parent'));
        END IF;    
    end_section;
	
 
   start_section('Single Document Reset Information');
      set_item_result(run_stored_sig('Note390023.1_case_GEN1'));
      IF nvl(p_trx_type,'PO') in ('PO','PA') THEN
        set_item_result(run_stored_sig('Note390023.1_case_GEN2'));
      END IF;
      IF nvl(p_trx_type,'REQUISITION') = 'REQUISITION' THEN
        set_item_result(run_stored_sig('Note390023.1_case_GEN3'));
      END IF;
      IF p_trx_type in ('PA','PO') THEN
        l_sql_result := run_stored_sig('Note390023.1_case_PO1');
        set_item_result(l_sql_result);
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO2');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO3');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO4');
          set_item_result(l_sql_result);
          IF l_sql_result <> 'S' THEN
             set_item_result(run_stored_sig('Note390023.1_case_PO4.1'));
          END IF;
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO5');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO6');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO7');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO8');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_PO9');
          set_item_result(l_sql_result);
        END IF;
      ELSIF p_trx_type = 'REQUISITION' THEN
        l_sql_result := run_stored_sig('Note390023.1_case_REQ1');
        set_item_result(l_sql_result);
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ2');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ3');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ4');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ5');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ6');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ7');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REQ8');
          set_item_result(l_sql_result);
        END IF;
      ELSIF p_trx_type = 'RELEASE' THEN
        l_sql_result := run_stored_sig('Note390023.1_case_REL1');
        set_item_result(l_sql_result);
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REL2');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REL3');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REL4');
          set_item_result(l_sql_result);
          IF l_sql_result <> 'S' THEN
            set_item_result(run_stored_sig('Note390023.1_case_REL4.1'));
          END IF;
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REL5');
          set_item_result(l_sql_result);
        END IF;
        IF l_sql_result = 'S' THEN
          l_sql_result := run_stored_sig('Note390023.1_case_REL6');
          set_item_result(l_sql_result);
        END IF;
      END IF;
    end_section;
  END IF;

  -- WFStat Section
  l_step := '80';
  IF p_trx_num IS NOT NULL AND p_include_wf = 'Y' THEN
    start_section('WFSTAT - Workflow Item Status');
    l_sql_result := run_stored_sig('WFSTAT_ITEM');
    set_item_result(l_sql_result);
    IF l_sql_result = 'S' THEN
      set_item_result(run_stored_sig('WFSTAT_CHILD_PROCESSES'));
      set_item_result(run_stored_sig('WFSTAT_ACTIVITY_STATUSES'));
      set_item_result(run_stored_sig('WFSTAT_ACTIVITY_STATUSES_HISTORY'));
      set_item_result(run_stored_sig('WFSTAT_NOTIFICATIONS'));
      set_item_result(run_stored_sig('WFSTAT_ERRORED_ACTIVITIES'));

      set_item_result(run_stored_sig('WFSTAT_ERROR_ORA_04061'));
      set_item_result(run_stored_sig('WFSTAT_ERROR_ORA_06512'));
      set_item_result(run_stored_sig('WFSTAT_ERROR_20002'));
      IF (p_trx_type = 'REQUISITION') THEN
         set_item_result(run_stored_sig('WFSTAT_Note1268145.1'));
         set_item_result(run_stored_sig('WFSTAT_Note1277855.1'));
         set_item_result(run_stored_sig('WFSTAT_Note1969021.1'));
         IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.2') THEN      -- signatures specific to R12.2
            set_item_result(run_stored_sig('WFSTAT_Note1961339.1'));         
            set_item_result(run_stored_sig('WFSTAT_Note1995413.1'));         
            set_item_result(run_stored_sig('Note1905401.1'));
            set_item_result(run_stored_sig('WFSTAT_Note1969203.1'));
         ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN 
            set_item_result(run_stored_sig('Note1905401.1'));
            set_item_result(run_stored_sig('WFSTAT_Note1969203.1'));
         END IF;
      ELSIF (p_trx_type = 'PO') THEN
         set_item_result(run_stored_sig('WFSTAT_Note1288874.1'));
      END IF;
      
      set_item_result(run_stored_sig('WFSTAT_ERROR_PROCESS_ACTIVITY_STATUS'));
      set_item_result(run_stored_sig('WFSTAT_ERROR_PROCESS_ACTIVITY_STATUS_HIST'));
      set_item_result(run_stored_sig('WFSTAT_ERROR_PROCESS_ERRORED_ACTIVITIES'));
      set_item_result(run_stored_sig('WFSTAT_ITEM_ATTRIBUTE_VALUES'));
      set_item_result(run_stored_sig('WFSTAT_EVENT_DATATYPE_ITEM_ATTR_VALUES'));
      set_item_result(run_stored_sig('PO_WF_DEBUG'));
    END IF;
    end_section;
  END IF;


  -- Approval Hierarchy / AME Validations
  l_step := '90';
  IF p_trx_num IS NOT NULL THEN

   IF g_use_ame THEN
      start_section('AME Information');
        set_item_result(get_ame_approvers);
        set_item_result(run_stored_sig('AME_RULES'));
        set_item_result(run_stored_sig('AME_APPR_GROUPS'));
        set_item_result(run_stored_sig('AME_MANDATORY_ATTR'));
        set_item_result(run_stored_sig('AME_ITEM_CLASSES'));
        set_item_result(run_stored_sig('AME_IC_ATTR'));
        set_item_result(run_stored_sig('AME_ACTION_TYPES'));
        set_item_result(run_stored_sig('AME_CONFIG_VARS'));
        if (g_sql_tokens('##$$AMETRXID$$##') IS NOT NULL) then
           set_item_result(get_ame_rules_for_trxn(g_sql_tokens('##$$AMETRXID$$##')));
           set_item_result(get_ame_approvers_for_trxn(g_sql_tokens('##$$AMETRXID$$##')));
        end if;   
      end_section;
    ELSE
    start_section(initcap(g_app_method)||' Hierarchy Approver List Validation');
      IF g_app_method = 'POSITION' THEN
        set_item_result(run_stored_sig('APP_POS_HIERARCHY_MAIN'));
      ELSE
        set_item_result(run_stored_sig('APP_SUP_HIERARCHY_MAIN'));
      END IF;
      end_section;
    END IF;
  END IF;

  -- Vacation Rules ?
  l_step := '100';
  

  -- AME and PO Package Versions
  l_step := '110';
  start_section('PO and AME File versions');
    set_item_result(run_stored_sig('PACKAGE_VERSIONS'));
    set_item_result(run_stored_sig('PO_WF_FILE_VERSIONS'));
  end_section;

  -- Proactive section
  l_step := '120';
  start_section('Proactive and Preventative Recommendations');
  l_step := '121';
     set_item_result(check_rec_patches);
  l_step := '122';
     set_item_result(run_stored_sig('WF_OVERALL_HEALTH'));
  l_step := '123';
     set_item_result(run_stored_sig('PO_INVALIDS'));
  l_step := '124';
     set_item_result(run_stored_sig('PO_WORKFLOW_APPROVAL_MODE'));
  l_step := '125';
     set_item_result(run_stored_sig('AME_ENABLED'));
     
-- commenting this one for performance reasons
--     set_item_result(run_stored_sig('TABLESPACE_CHECK'));

  end_section;

  -- PO Workflow debug information?

  -- Single trx data validations
  IF p_trx_num IS NOT NULL THEN
    l_step := '130';
    start_section('Single Document Data Integrity Validation');
    IF p_trx_type in ('PO','PA','RELEASE') THEN
      IF p_trx_type in ('PO','PA') THEN
        l_sql_result := run_stored_sig('DATA_SINGLE_PO1');
        set_item_result(l_sql_result);

        set_item_result(run_stored_sig('DATA_SINGLE_PO2'));
        set_item_result(run_stored_sig('DATA_SINGLE_PO3'));
        set_item_result(run_stored_sig('DATA_SINGLE_PO4'));
        set_item_result(run_stored_sig('DATA_SINGLE_PO5'));
        
      ELSIF p_trx_type = 'RELEASE' THEN
        set_item_result(run_stored_sig('DATA_SINGLE_REL1'));
        set_item_result(run_stored_sig('DATA_SINGLE_REL2'));
        set_item_result(run_stored_sig('DATA_SINGLE_REL3'));
        set_item_result(run_stored_sig('DATA_SINGLE_REL4'));
      END IF;
      set_item_result(run_stored_sig('DATA_SINGLE_POREL1'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL2'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL3'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL4'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL5'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL6'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL7'));
      set_item_result(run_stored_sig('DATA_SINGLE_POREL8'));
      set_item_result(run_stored_sig('UPGRADE_SINGLE'));
    ELSIF p_trx_type = 'REQUISITION' THEN
      set_item_result(run_stored_sig('DATA_SINGLE_REQ1'));
      set_item_result(run_stored_sig('DATA_SINGLE_REQ2'));
      set_item_result(run_stored_sig('DATA_SINGLE_REQ3'));
      set_item_result(run_stored_sig('UPGRADE_SINGLE'));
    END IF;
    end_section('No data validation issues found '||
      'with this document.');
  END IF;

  IF (p_trx_num IS NOT NULL) AND ((p_trx_type = 'PO') OR (p_trx_type = 'REQUISITION')) THEN
    l_step := '135';

    start_section('Document Manager Errors');
         set_item_result(run_stored_sig('Note1310935.1_case_1'));
         set_item_result(run_stored_sig('Note1304639.1_case_4'));
         set_item_result(run_stored_sig('Note1304639.1_case_5'));
         set_item_result(run_stored_sig('Note1116134.1'));
         set_item_result(run_stored_sig('Note985937.1'));
         set_item_result(run_stored_sig('Note312582.1_SINGLE'));
         
         IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') OR (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
             set_item_result(run_stored_sig('Note1073703.1'));
             set_item_result(run_stored_sig('Note1370218.1'));
         END IF;
      IF (p_trx_type = 'PO') THEN
         set_item_result(run_stored_sig('Note1304639.1_case_1'));
         set_item_result(run_stored_sig('Note1304639.1_case_2'));
         set_item_result(run_stored_sig('Note1097585.1'));
         IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') OR (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
             set_item_result(run_stored_sig('Note1317504.1'));
         END IF;
      ELSE 
         set_item_result(run_stored_sig('Note1304639.1_case_3'));
         set_item_result(run_stored_sig('Note1304639.1_case_6'));
         set_item_result(run_stored_sig('Note1304639.1_case_7'));
      END IF;    

    end_section('No Document Manager Errors Found.');
    
  ELSIF (p_trx_num IS NOT NULL) AND (p_trx_type = 'RELEASE') 
    AND ((substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') OR (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1')) 
    THEN
    l_step := '136';  
    start_section('Document Manager Errors');
        set_item_result(run_stored_sig('Note867855.1'));      
    end_section('No Document Manager Errors Found.');
  END IF;
  
  
  -- Recent Document Reset Information
  IF p_trx_num is null THEN
    l_step := '138';   
    start_section('Change Requests');
        set_item_result(run_stored_sig('PO_CHANGE_ORDER_TOLERANCE'));
    end_section;
    
    start_section('Recent Documents Reset Information');
      set_item_result(run_stored_sig('Note390023.1_case_GEN1'));
      set_item_result(run_stored_sig('Note390023.1_case_GEN2'));
      set_item_result(run_stored_sig('Note390023.1_case_GEN3'));
    -- moved inside the IF clause because this is generic  
      set_item_result(run_stored_sig('Note390023.1_case_GEN4'));
    end_section;
    
    -- Document Manager Errors
    -- Moved section inside the IF, because it is for recent document scenario
    l_step := '140';
    start_section('Document Manager Errors');
       set_item_result(run_stored_sig('Note1310935.1_case_1'));
       set_item_result(run_stored_sig('Note1304639.1_case_1'));
       set_item_result(run_stored_sig('Note1304639.1_case_2'));
       set_item_result(run_stored_sig('Note1304639.1_case_3'));
       set_item_result(run_stored_sig('Note1304639.1_case_4'));
       set_item_result(run_stored_sig('Note1304639.1_case_5'));
       set_item_result(run_stored_sig('Note1304639.1_case_6'));
       set_item_result(run_stored_sig('Note1304639.1_case_7'));
       set_item_result(run_stored_sig('Note312582.1_ALL'));
       set_item_result(run_stored_sig('Note1116134.1'));
       IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') OR (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
          set_item_result(run_stored_sig('Note867855.1'));
          set_item_result(run_stored_sig('Note1073703.1'));
          set_item_result(run_stored_sig('Note1370218.1'));
          set_item_result(run_stored_sig('Note1317504.1'));
       END IF;
       set_item_result(run_stored_sig('Note985937.1'));
    end_section('No Document Manager Errors Found.');
    
    
    -- Recent document data validations 
    -- Moved section inside the IF, because it is for recent document scenario
    l_step := '150';
    start_section('Recent Document Data Integrity Validation');
      set_item_result(run_stored_sig('DATA_RANGE_GEN1'));
      set_item_result(run_stored_sig('DATA_RANGE_PO1'));
      set_item_result(run_stored_sig('DATA_RANGE_PO2'));
      set_item_result(run_stored_sig('DATA_RANGE_PO3'));
      set_item_result(run_stored_sig('DATA_RANGE_PO4'));
      set_item_result(run_stored_sig('DATA_RANGE_PO5'));
      set_item_result(run_stored_sig('DATA_RANGE_REL1'));
      set_item_result(run_stored_sig('DATA_RANGE_REL2'));
      set_item_result(run_stored_sig('DATA_RANGE_REL3'));
      set_item_result(run_stored_sig('DATA_RANGE_REL4'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL1'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL2'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL3'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL4'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL5'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL6'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL7'));
      set_item_result(run_stored_sig('DATA_RANGE_POREL8'));
      set_item_result(run_stored_sig('DATA_RANGE_REQ1'));
      set_item_result(run_stored_sig('DATA_RANGE_REQ2'));
      set_item_result(run_stored_sig('DATA_RANGE_REQ3'));
      set_item_result(run_stored_sig('UPGRADE_ALL'));
    end_section('No data validation issues found '||
      'for this operating unit and date range.');
  END IF;


  l_step := '160';
  start_section('Organization Document Type Setup');
    set_item_result(run_stored_sig('ORG_DOC_TYPES'));
    IF g_use_ame THEN
      set_item_result(run_stored_sig('DOC_PO_STYLE_HEADER'));  
    END IF;             
   end_section;
  
  l_step := '165';
  
  start_section('Procurement Code Level');
    IF (g_sql_tokens('##$$REL$$##') IS NOT NULL) THEN
       IF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.0') THEN
          set_item_result(run_stored_sig('PROC_CODE_LEVEL_12_0'));
       ELSIF (substr(g_sql_tokens('##$$REL$$##'),1,4) = '12.1') THEN
          set_item_result(run_stored_sig('PROC_CODE_LEVEL_12_1'));
       ELSE
          set_item_result(run_stored_sig('PROC_CODE_LEVEL_12_2'));    
       END IF;
    END IF;   
    
  end_section;
  -- End of Sections and signatures
  
  print_out('</div>');

  -- End of report, print TOC
  l_step := '140';
  print_toc_contents;
  
  g_analyzer_elapsed := stop_timer(g_analyzer_start_time);
  get_current_time(l_analyzer_end_time);
  
  print_out('<hr><br><table width="40%"><thead><strong>Performance Data</strong></thead>');
  print_out('<tbody><tr><th>Started at:</th><td>'||to_char(g_analyzer_start_time,'hh24:mi:ss.ff3')||'</td></tr>');
  print_out('<tr><th>Complete at:</th><td>'||to_char(l_analyzer_end_time,'hh24:mi:ss.ff3')||'</td></tr>');
  print_out('<tr><th>Total time:</th><td>'||format_elapsed(g_analyzer_elapsed)||'</td></tr>');
  print_out('</tbody></table>');
  
  print_out('<br><hr>');
  print_out('<strong>Still have questions or suggestions?</strong><br>');
  print_out('<a href="https://community.oracle.com/message/12964973#12964973" target="_blank">');
  print_out('<img border="0" src="https://blogs.oracle.com/ebs/resource/Proactive/Feedback_75.gif" title="Click here to provide feedback for this Analyzer">');
  print_out('</a><br><span class="regtext">');
  print_out('Click the button above to ask questions about and/or provide feedback on the ' || analyzer_title ||  ' Analyzer. Share your recommendations for enhancements and help us make this Analyzer even more useful!');  
  print_out('</span>');

  print_hidden_xml;
  
  close_files; 
  
EXCEPTION WHEN others THEN
  g_retcode := 2;
  g_errbuf := 'Error in main at step '||l_step||': '||sqlerrm;
  print_log(g_errbuf);
   
END main;

---------------------------------
-- MAIN ENTRY POINT FOR CONC PROC
---------------------------------
PROCEDURE main_cp(  
      errbuf            OUT VARCHAR2,
      retcode           OUT VARCHAR2,
      p_mode            IN VARCHAR2,  
      p_org_id          IN NUMBER,    
      p_dummy1          IN VARCHAR2,  
      p_trx_type        IN VARCHAR2,  
      p_dummy2          IN VARCHAR2,  
      p_po_num          IN VARCHAR2,  
      p_dummy3          IN VARCHAR2,  
      p_release_num     IN NUMBER,    
      p_dummy4          IN VARCHAR2,  
      p_req_num         IN VARCHAR2,  
      p_from_date       IN VARCHAR2,  
      p_max_output_rows IN NUMBER,    
      p_debug_mode      IN VARCHAR2) IS

l_trx_type  VARCHAR2(30);
l_trx_num   VARCHAR2(25);
l_from_date DATE := fnd_conc_date.string_to_date(p_from_date);
l_step      VARCHAR2(5);

BEGIN
  l_step := '10';
  g_retcode := '0';
  g_errbuf := null;
  l_trx_type := p_trx_type;  
  l_trx_num := nvl(p_po_num, p_req_num);  
  l_step := '20';
  

  IF (l_trx_type IS NULL) THEN
     l_trx_type := 'ANY';
  END IF;
  
  main(
      p_mode => p_mode,  
      p_org_id => p_org_id,
      p_trx_type => l_trx_type,
      p_trx_num => l_trx_num,
      p_release_num => p_release_num,
      p_from_date => l_from_date,
      p_max_output_rows => p_max_output_rows,
      p_debug_mode => p_debug_mode,
      p_calling_from => 'Concurrent Program');

  l_step := '30';
  retcode := g_retcode;
  errbuf  := g_errbuf;
EXCEPTION WHEN OTHERS THEN
  retcode := '2';
  errbuf := 'Error in main_cp:'||l_step||' '||sqlerrm||' : '||g_errbuf;
END main_cp;

END po_apprvl_analyzer_pkg;
/
show errors
exit;