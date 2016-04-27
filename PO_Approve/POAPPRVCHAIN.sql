--alter session set nls_date_language='AMERICAN';
--alter session set nls_language='AMERICAN';
--show parameter nls_date_language;
--show parameter nls_language;
REM $Header: POAPPRVCHAIN.sql 12.0  fbuitrag ship $
REM=======================================================================+
REM |    Copyright (c) 2002 Oracle Corporation, Redwood Shores, CA, USA     |
REM |                         All rights reserved.                          |
REM=======================================================================+
REM | FILENAME                                                              |
REM |     POAPPRVCHAIN.sql                                                  |
REM |                                                                       |
REM | DESCRIPTION                                                           |
REM |     This SQL script is is intended to help troubleshoot issues        |
REM |     with approval hierarchies                                         |
REM |                                                                       |
REM | NOTE                                                                  |
REM |     This SQL script can be run from SQLPLUS                           |
REM |                                                                       |
REM | INPUT/OUTPUT                                                          |
REM |     Inputs :                                                          |
REM |                                                                       |
REM |     Output :                                                          |
REM |                                                                       |
REM | HISTORY                                                               |
REM |     20-FEB-2012              fbuitrag              CREATED            | 
REM=======================================================================+

REM dbdrv: none

SET VERIFY OFF
Whenever Oserror Continue;
--WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

clear buffer;

set heading on
Set Feed Off
set linesize 500
set pagesize 5000
set underline '='
set SERVEROUTPUT on size 1000000


-------------------------
-- Variables definition
-------------------------

variable v_org_id                number;
variable v_sec_prof_id           number;
variable V_USER_Id               number;
variable V_Respid_Entered        number;
variable V_Application_Id        number;
variable v_approval_method       varchar2(20);
variable v_doc_type              varchar2(20);
variable v_doc_subtype           varchar2(20);
variable v_doc_hdr_id            number;
variable v_release_num           number;
variable v_currency              varchar2(10);
variable v_doc_precision         number;
variable v_ext_prec              number
variable doc_min_acct_unit       number;
variable v_doc_nettotal          number;
variable v_doc_tax               number;
variable v_emp_derived_from      varchar2(100);
variable v_employee_id           number;
variable v_prp_position_id       number;
variable v_prp_position          varchar2(100);
variable v_prp_job_id            number;
variable v_prp_job_name          varchar2(100);
variable v_prp_location_code     varchar2(100);
variable v_prp_business_group_id number;
variable v_prp_supervisor_id     number;
variable v_prp_user_name         varchar2(100);
variable v_job_id                number;
variable v_job_name              number;
variable v_apprv_path_id         number;
variable v_ame_trx_type          varchar2(20);
variable v_Can_preparer_apprv    varchar2(1);
variable v_apprv_hierarchy       varchar2(30);       
variable v_curr_emp_id           number;      
variable v_next_emp_id           number;
variable v_fullname              varchar2(100);
variable v_sup_id                number;
variable v_sup_level             number;
variable v_sup_name              varchar2(100);
variable v_curr_position         number;
variable v_ret_status            varchar2(10);
variable v_ret_code              varchar2(100);
variable v_exception_msg         varchar2(2000);
variable v_auth_fail_msg         varchar2(2000);

-----------------------
-- Parameters section
-----------------------


accept USER_NAME PROMPT 'Enter the username :'

declare 
  L_TEST NUMBER;
begin
   select user_id into :V_USER_ID
   from FND_USER
   where user_name = upper('&&USER_NAME')
   and rownum = 1;
EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - User name not found in FND_USER table. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/


COL user_name format a30

PROMPT 
PROMPT list of AVAILABLE PURCHASING RESPONSIBILITIES for user:
select USER_ID, user_name, employee_id from FND_USER
where user_id = :V_USER_ID;


Prompt 
Select urg.Responsibility_Id RESP_ID, rt.responsibility_name RESP_NAME
From Fnd_User_Resp_Groups urg, 
Fnd_Responsibility_Tl Rt
Where Urg.User_Id = :v_user_id
And Urg.Responsibility_Application_Id = (Select Fa.Application_Id From Fnd_Application Fa Where Application_Short_Name =  'PO')
And Rt.Responsibility_Id = Urg.Responsibility_Id;

prompt 'new lines--------------------------'

begin 
   select &&RESPONSIBILITY_ID into :V_RESPID_ENTERED  from FND_RESPONSIBILITY
   where responsibility_id = &&RESPONSIBILITY_ID;

   EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - Responsibility ID not found. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/

-- Set user context


begin

  Select Fa.Application_Id Into :V_Application_Id
  From Fnd_Application Fa Where Application_Short_Name =  'PO';

-- set user context to get profile option values
  Fnd_Global.Apps_Initialize(:V_USER_Id, :V_Respid_Entered, :V_Application_Id);
  
  select Fnd_Profile.Value('ORG_ID') into :v_org_id from dual;
--  select Fnd_Profile.Value('ORG_ID'), FND_PROFILE.value('XLA_MO_SECURITY_PROFILE_LEVEL') into :v_org_id, :v_sec_prof_id from dual;
  
  mo_global.set_policy_context('S', :v_org_id);
  --mo_global.set_org_access(:v_org_id, :v_sec_prof_id, 'PO');
end;
/

-- `
accept DOCUMENT_TYPE prompt 'Enter Document type (PO,REQ, RELEASE, PA) :'
declare
 v_type  varchar2(30);
begin 
   v_type:=upper('&&DOCUMENT_TYPE');
    if v_type='REQ'
    then 
    v_type:='REQUISITION';
    end if;

   select document_type_code into :v_doc_type  from  PO_DOCUMENT_TYPES
   where document_type_code = v_type
   and rownum = 1;

   EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - Could not find document type &&DOCUMENT_TYPE in this operating unit. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/

-- Document subtype
prompt
prompt Available Document Subtypes
prompt

select distinct document_subtype from  PO_DOCUMENT_TYPES
where document_type_code = :v_doc_type;

prompt 

accept DOCUMENT_SUBTYPE prompt 'Enter Document Subtype :'

begin 
   select document_subtype into :v_doc_subtype  from  PO_DOCUMENT_TYPES
   where document_type_code = :v_doc_type
   and   document_subtype = upper('&&DOCUMENT_SUBTYPE');

   EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - Counld not find document type &&DOCUMENT_TYPE, document subtype &&DOCUMENT_SUBTYPE in this operating unit. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/


accept DOCUMENT_NUMBER prompt 'Enter Document Number :'
accept RELEASE_NUMBER prompt 'Enter the release number if it is a release :'

begin 
   select '&&RELEASE_NUMBER' into :v_release_num from dual;
   if :v_doc_type = 'PO' or :v_doc_type = 'PA' then
      select po_header_id into :v_doc_hdr_id  from  PO_headers
      where segment1 = '&&DOCUMENT_NUMBER';
   elsif :v_doc_type = 'REQUISITION' then
      select requisition_header_id into :v_doc_hdr_id  from  PO_requisition_headers
      where segment1 = '&&DOCUMENT_NUMBER';
   else
      select pr.po_release_id into :v_doc_hdr_id  
      from  PO_releases pr, po_headers ph
      where ph.segment1 = &&DOCUMENT_NUMBER
      and   ph.po_header_id = pr.po_header_id
      and   pr.release_num = :v_release_num;
   end if;
   
   EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - Counld not find specified document number &&DOCUMENT_NUMBER in this operating unit. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/

-- Document Subtype


-----------------
--Data section
----------------

SPOOL POAPPRVCHAIN&&DOCUMENT_NUMBER-&&RELEASE_NUMBER

Prompt 
Prompt Script Version
Prompt ==============
Prompt $header: POAPPRVCHAIN.Sql 120.1 $
PROMPT

col dtime format a23 heading 'Script run at Date/Time' ;
select to_char(sysdate, 'DD-MON-YYYY HH:MI:SS') dtime from dual;

COL DTIME FORMAT A23 HEADING 'Database Name' ;
COL DB_NAME format a30
select  value DB_NAME from V$PARAMETER where name = 'db_name';

col user_resp format a250 heading 'Script run by User/Responsibility' ;

select 'Script run by user '||fu.user_name||', logged in as '||frv.responsibility_name||', for Organization ID '||:v_org_id  user_resp 
from   fnd_user fu, fnd_responsibility_vl frv
where  fu.user_id            = fnd_profile.value('USER_ID')
and    FRV.APPLICATION_ID    = FND_PROFILE.value('RESP_APPL_ID')
And    Frv.Responsibility_Id = Fnd_Profile.Value('RESP_ID');



prompt
PROMPT
prompt PO Financial Options
PROMPT =====================
PROMPT

SELECT decode (A.USE_POSITIONS_FLAG, 'Y', 'Position hierarchy', 'Employee/Supervisor') APPROVAL_METHOD
FROM financials_system_parameters a;

begin 
   SELECT decode (A.USE_POSITIONS_FLAG, 'Y', 'POSITION', 'SUPERVISOR') APPROVAL_METHOD
   into  :v_approval_method
   FROM financials_system_parameters a;

   EXCEPTION
   when NO_DATA_FOUND then
      DBMS_OUTPUT.PUT_LINE('ERROR - Could not find financial system parameters for this organization. Please enter Ctrl-C to cancel the execution of the script and check the parameters');
end;
/

prompt
PROMPT
prompt PO Document Types
PROMPT =====================
PROMPT

SELECT dt.TYPE_NAME DOCUMENT_TYPE,   
dt.document_type_code TYPE_CODE, 
DECODE(dt.CAN_PREPARER_APPROVE_FLAG,'Y','YES','NO') CAN_OWNER_APPROVE,   
dt.FORWARDING_MODE_CODE FORWARDING_METHOD,   
s.NAME HIERARCHY_NAME,   
wfit.DISPLAY_NAME WORKFLOW_PROCESS,   
wfrp.display_name WORKFLOW_TOP_PROCESS,  
dt.AME_TRANSACTION_TYPE AME_TRANSACTION_TYPE  
FROM   
PO_DOCUMENT_TYPES dt,   
PER_POSITION_STRUCTURES s,   
wf_item_types_vl wfit,   
wf_runnable_processes_v wfrp   
WHERE   
dt.DEFAULT_APPROVAL_PATH_ID = s.POSITION_STRUCTURE_ID(+) 
and wfit.NAME(+) = dt.WF_APPROVAL_ITEMTYPE 
and dt.WF_APPROVAL_PROCESS = wfrp.PROCESS_NAME(+) 
and dt.DOCUMENT_TYPE_CODE not in ('RFQ','QUOTATION');
     
     
prompt
PROMPT
prompt Document Type Detail
PROMPT =====================
PROMPT
COL DOCUMENT_TYPE_CODE          format a15
COL DOCUMENT_SUBTYPE            format a15
COL LAST_UPDATE_DATE            format a12
COL FORWARDING_MODE_CODE        format a15 heading FORWARD_METHD
COL DEFAULT_APPROVAL_PATH_ID    format 99999999999999 heading DEF_APPRV_PATH
COL CAN_PREPARER_APPROVE_FLAG   format a5 Heading CAN_PREPARER_APPROVE
COL CAN_CHANGE_APPROVAL_PATH_FLAG      format a21 heading CAN_CHG_APPROVAL_PATH
COL WF_APPROVAL_ITEMTYPE        format a15
COL WF_APPROVAL_PROCESS         format a15
COL AME_TRANSACTION_TYPE        format a15



SELECT ORG_ID, DOCUMENT_TYPE_CODE, DOCUMENT_SUBTYPE, LAST_UPDATE_DATE, FORWARDING_MODE_CODE, DEFAULT_APPROVAL_PATH_ID, CAN_PREPARER_APPROVE_FLAG, CAN_CHANGE_APPROVAL_PATH_FLAG, WF_APPROVAL_ITEMTYPE, WF_APPROVAL_PROCESS, AME_TRANSACTION_TYPE  
FROM po_document_types  
WHERE  document_type_code = :v_doc_type  
AND document_subtype =:v_doc_subtype;

-- store document type values
declare 

cursor C1 is 
   SELECT ORG_ID, DOCUMENT_TYPE_CODE, DOCUMENT_SUBTYPE, LAST_UPDATE_DATE, FORWARDING_MODE_CODE, DEFAULT_APPROVAL_PATH_ID, CAN_PREPARER_APPROVE_FLAG, 
          CAN_CHANGE_APPROVAL_PATH_FLAG, WF_APPROVAL_ITEMTYPE, WF_APPROVAL_PROCESS, AME_TRANSACTION_TYPE  
   FROM po_document_types  
   WHERE  document_type_code = :v_doc_type  
   AND document_subtype =:v_doc_subtype;


begin
   for i in C1 loop
      :v_apprv_path_id  := i.DEFAULT_APPROVAL_PATH_ID;
      :v_ame_trx_type   := i.AME_TRANSACTION_TYPE;
      :v_Can_preparer_apprv := i.CAN_PREPARER_APPROVE_FLAG;
      
      if :v_ame_trx_type is not null then
         dbms_output.put_line('WARNING: This document type/subtype is using Approvals manager (AME) for approvals');
         dbms_output.put_line('This test is not designed to work with AME');
      end if;
      if nvl(:v_Can_preparer_apprv, 'N') = 'N'  then 
         dbms_output.put_line('Warning: Owner can approve flag is disabled.');
         dbms_output.put_line('Enable this flag if you expect the preparer to be able to approve the document.');
      end if;   
   end loop;
end;
/

-- Calculate document totals
begin
--> TO change default currency 
  :v_currency := 'USD';
  FND_CURRENCY.GET_INFO(:v_currency, :v_doc_precision, :v_ext_prec, :doc_min_acct_unit);
  :doc_min_acct_unit := nvl(:doc_min_acct_unit, 0);  
  
  :v_doc_nettotal := po_notifications_sv3.get_doc_total(:v_doc_subtype, :v_doc_hdr_id);
 
  if :v_doc_type = 'PO' then
    if :doc_min_acct_unit > 0 then
       SELECT nvl(sum( round (POD.nonrecoverable_tax *  decode(quantity_ordered, NULL,
                       (nvl(POD.amount_ordered,0) - nvl(POD.amount_cancelled,0)) / nvl(POD.amount_ordered, 1),
                       (nvl(POD.quantity_ordered,0) - nvl(POD.quantity_cancelled,0)) / nvl(POD.quantity_ordered, 1)
                   ) / :doc_min_acct_unit
               ) * :doc_min_acct_unit )
         , 0) DOCUMENT_TAX 
         into :v_doc_tax
         FROM po_distributions POD 
         WHERE po_header_id = :v_doc_hdr_id;
    else
         SELECT nvl(sum
           ( round 
               (POD.nonrecoverable_tax *  
                   decode(quantity_ordered,  
                       NULL,
                       (nvl(POD.amount_ordered,0) - nvl(POD.amount_cancelled,0)) / nvl(POD.amount_ordered, 1),
                       (nvl(POD.quantity_ordered,0) - nvl(POD.quantity_cancelled,0)) / nvl(POD.quantity_ordered, 1)
                   ), :v_doc_precision
               )
            )
           , 0) DOCUMENT_TAX
        into :v_doc_tax
        FROM po_distributions_all POD 
        WHERE po_header_id = :v_doc_hdr_id;
    end if;
  elsif :v_doc_type = 'RELEASE' then
    if :doc_min_acct_unit > 0 then
          SELECT nvl(sum
           ( round (POD.nonrecoverable_tax *  decode(quantity_ordered,  NULL,(nvl(POD.amount_ordered,0) - nvl(POD.amount_cancelled,0)) / nvl(POD.amount_ordered, 1),
                       (nvl(POD.quantity_ordered,0) - nvl(POD.quantity_cancelled,0)) / nvl(POD.quantity_ordered, 1)
                   ) / :doc_min_acct_unit
               ) * :doc_min_acct_unit )
           , 0) DOCUMENT_TAX
           into :v_doc_tax
           FROM po_distributions_all POD
          WHERE po_release_id =  :v_doc_hdr_id;
    else     
        SELECT nvl( sum( round (POD.nonrecoverable_tax * decode(quantity_ordered, NULL,
                           (nvl(POD.amount_ordered,0) - nvl(POD.amount_cancelled,0)) / nvl(POD.amount_ordered, 1),
                           (nvl(POD.quantity_ordered,0) - nvl(POD.quantity_cancelled,0)) / nvl(POD.quantity_ordered, 1)
                       ), :v_doc_precision ) )
            , 0) DOCUMENT_TAX
         into :v_doc_tax
         FROM po_distributions_all POD 
         WHERE po_release_id =  :v_doc_hdr_id;
    end if;
  elsif :v_doc_type = 'REQUISITION' then
        SELECT nvl(sum(nonrecoverable_tax), 0) DOCUMENT_TAX
        into :v_doc_tax
        FROM   po_requisition_lines rl, 
               po_req_distributions_all rd 
        WHERE  rl.requisition_header_id = :v_doc_hdr_id 
        AND  rd.requisition_line_id = rl.requisition_line_id 
        AND  NVL(rl.cancel_flag,'N') = 'N'  
        AND  NVL(rl.modified_by_agent_flag, 'N') = 'N' ;
  else
        :v_doc_tax := 0;
  end if;
    
end;
/

prompt
PROMPT
prompt Document Header 
PROMPT ================
PROMPT

COL PO_NUMBER format 9999999999
COL approved_flag format a9  heading APPRV_FLG
COL APPROVED_DATE format a12
COL approval_required_flag format a9 heading APPRV_REQ
col WF_ITEM_KEY format a30
col GLOBAL_AGREEMENT_FLAG format a8  heading GLOB_AGR
col ENCUMBRANCE_REQUIRED_FLAG format a8 heading ENCU_REQ
col SUMMARY_FLAG  format a7 heading SUM_FLG
Col ENABLED_FLAG format a8 heading ENAB_FLG
SELECT
    po_header_id HEADER_ID,
    segment1 PO_NUMBER,
    approved_flag,
    APPROVED_DATE, 
    approval_required_flag,
    authorization_status, 
-- cancel_flag,
    org_id,
    submit_date,
    :v_doc_nettotal DOCUMENT_NET,
    :v_doc_tax DOCUMENT_TAX,
    :v_doc_nettotal+:v_doc_tax TOTAL_PLUS_TAX,
    :v_doc_precision CURRENCY_PRECISION,
    :v_ext_prec CURRENCY_EXT_PRECISION,
    :doc_min_acct_unit MIN_ACCOUNT_UNIT,
    LAST_UPDATE_DATE,
    LAST_UPDATED_BY,
    SUMMARY_FLAG,
    ENABLED_FLAG,
    --SEGMENT2,
    --SEGMENT3,
    --SEGMENT4,
    --SEGMENT5,
    --START_DATE_ACTIVE,
    --END_DATE_ACTIVE,
    --LAST_UPDATE_LOGIN,
    CREATION_DATE,
    --CREATED_BY,
    --VENDOR_ID,
    --VENDOR_SITE_ID,
    --VENDOR_CONTACT_ID,
    --SHIP_TO_LOCATION_ID,
    --BILL_TO_LOCATION_ID,
    --TERMS_ID,
    --SHIP_VIA_LOOKUP_CODE,
    --FOB_LOOKUP_CODE,
    --FREIGHT_TERMS_LOOKUP_CODE,
    --STATUS_LOOKUP_CODE,
    CURRENCY_CODE,
    RATE_TYPE,
    RATE_DATE,
    RATE,
    --FROM_HEADER_ID,
    --FROM_TYPE_LOOKUP_CODE,
    --START_DATE,
    --END_DATE,
    BLANKET_TOTAL_AMOUNT,
    AUTHORIZATION_STATUS,
    REVISION_NUM, 
    REVISED_DATE,
    AMOUNT_LIMIT,
    MIN_RELEASE_AMOUNT,
--    NOTE_TO_AUTHORIZER,
--    NOTE_TO_VENDOR,
--    NOTE_TO_RECEIVER,
    --PRINT_COUNT,
    --PRINTED_DATE,
    --VENDOR_ORDER_NUM,
    --CONFIRMING_ORDER_FLAG,
--    REPLY_DATE,
--  REPLY_METHOD_LOOKUP_CODE,
    --ACCEPTANCE_REQUIRED_FLAG,
    --ACCEPTANCE_DUE_DATE,
    CLOSED_DATE,
    --USER_HOLD_FLAG,
    APPROVAL_REQUIRED_FLAG,
    --FIRM_STATUS_LOOKUP_CODE,
    --FIRM_DATE,
    --FROZEN_FLAG,
    --SUPPLY_AGREEMENT_FLAG,
    --EDI_PROCESSED_FLAG,
    --EDI_PROCESSED_STATUS,
    INTERFACE_SOURCE_CODE,
    --REFERENCE_NUM,
    WF_ITEM_TYPE,
    WF_ITEM_KEY,
--    MRC_RATE_TYPE,
--    MRC_RATE_DATE,
--    MRC_RATE,
--    PCARD_ID,
--    PRICE_UPDATE_TOLERANCE,
--    PAY_ON_CODE,
--    XML_FLAG,
--    XML_SEND_DATE,
--    XML_CHANGE_SEND_DATE,
    GLOBAL_AGREEMENT_FLAG,
    ENCUMBRANCE_REQUIRED_FLAG,
    --PENDING_SIGNATURE_FLAG,
--    CHANGE_SUMMARY,
    DOCUMENT_CREATION_METHOD
from po_headers
where po_header_id = :v_doc_hdr_id
and :v_doc_type in ('PO', 'PA');

SELECT
    PO_RELEASE_ID, 
    po_header_id, 
    (select segment1 from po_headers ph where ph.po_header_id = pr.po_header_id) PO_NUMBER,
    release_num,
    revision_num, 
    approved_flag, 
    approved_date, 
    --acceptance_required_flag,
    authorization_status, 
    --hold_flag,
    --cancel_flag, 
    closed_code, 
    release_type, 
    org_id, 
    :v_doc_nettotal DOCUMENT_NET,
    :v_doc_tax DOCUMENT_TAX,
    :v_doc_nettotal+:v_doc_tax TOTAL_PLUS_TAX,
    :v_doc_precision CURRENCY_PRECISION,
    :v_ext_prec CURRENCY_EXT_PRECISION,
    :doc_min_acct_unit MIN_ACCOUNT_UNIT,
    RELEASE_DATE,
    AGENT_ID,
    --PRINT_COUNT,
    --PRINTED_DATE,
    --HOLD_BY,
    --HOLD_DATE,
    --HOLD_REASON,
    --CANCELLED_BY,
    --CANCEL_DATE,
    --CANCEL_REASON,
    --FIRM_STATUS_LOOKUP_CODE,
    --FIRM_DATE,
    --USSGL_TRANSACTION_CODE,
    --GOVERNMENT_CONTEXT,
    --FROZEN_FLAG,
    --EDI_PROCESSED_FLAG,
    WF_ITEM_TYPE,
    WF_ITEM_KEY,
    --PCARD_ID,
    --PAY_ON_CODE,
    --XML_FLAG,
    --XML_SEND_DATE,
    --XML_CHANGE_SEND_DATE,
    --CONSIGNED_CONSUMPTION_FLAG,
    --CBC_ACCOUNTING_DATE,
    --CHANGE_REQUESTED_BY,
    --CHANGE_SUMMARY,
    --VENDOR_ORDER_NUM,
    --DOCUMENT_CREATION_METHOD,
    SUBMIT_DATE
    --TAX_ATTRIBUTE_UPDATE_CODE
FROM PO_RELEASES pr
WHERE PO_RELEASE_ID = :v_doc_hdr_id
and :v_doc_type  = 'RELEASE';


SELECT
    requisition_header_id HEADER_ID,
    segment1 DOC_NUMBER,
    authorization_status APPROVAL_STATUS,
    type_lookup_code REQUISITION_TYPE,
    authorization_status,
    approved_date, 
    interface_source_code,
    org_id,
    :v_doc_nettotal DOCUMENT_NET,
    :v_doc_tax DOCUMENT_TAX,
    :v_doc_nettotal+:v_doc_tax TOTAL_PLUS_TAX,
    :v_doc_precision CURRENCY_PRECISION,
    :v_ext_prec CURRENCY_EXT_PRECISION,
    :doc_min_acct_unit MIN_ACCOUNT_UNIT,
    PREPARER_ID,
    LAST_UPDATE_DATE,
    LAST_UPDATED_BY,
    SUMMARY_FLAG,
    ENABLED_FLAG,
    --SEGMENT2,
    --SEGMENT3,
    --SEGMENT4,
    --SEGMENT5,
    --START_DATE_ACTIVE,
    --END_DATE_ACTIVE,
    --CREATION_DATE,
    --CREATED_BY,
    --TRANSFERRED_TO_OE_FLAG,
    --USSGL_TRANSACTION_CODE,
    --GOVERNMENT_CONTEXT,
    --INTERFACE_SOURCE_CODE,
    --INTERFACE_SOURCE_LINE_ID,
    CLOSED_CODE,
    WF_ITEM_TYPE,
    WF_ITEM_KEY,
    --EMERGENCY_PO_NUM,
    --PCARD_ID,
    --APPS_SOURCE_CODE,
    --CBC_ACCOUNTING_DATE,
    CHANGE_PENDING_FLAG,
    --ACTIVE_SHOPPING_CART_FLAG,
    --CONTRACTOR_STATUS,
    --CONTRACTOR_REQUISITION_FLAG,
    --SUPPLIER_NOTIFIED_FLAG,
    --EMERGENCY_PO_ORG_ID,
    APPROVED_DATE,
    --TAX_ATTRIBUTE_UPDATE_CODE,
    FIRST_APPROVER_ID,
    FIRST_POSITION_ID
FROM PO_REQUISITION_HEADERS
WHERE REQUISITION_HEADER_ID = :v_doc_hdr_id
and :v_doc_type = 'REQUISITION';


prompt 
prompt 



PROMPT 
PROMPT Document Lines
Prompt ==================
Prompt 

COL item_number format a20
col item_name format  a20
col item_category format a20

SELECT 
     Line_Location_ID, 
     Shipment_num, 
     shipment_type, 
     Item_ID, 
     Item_Description ITEM_NAME, 
     ITEM_REVISION, 
     Category ITEM_CATEGORY, 
     CATEGORY_ID, 
     Quantity, 
     Unit_Meas_Lookup_Code UOM, 
     Unit_Price, 
     Price_Override Discounted_price,
     Currency_Code, 
     Taxable_flag, 
     Tax_Name, 
     TAX_USER_OVERRIDE_FLAG, 
     TAX_CODE_ID, 
     SOURCE_LINE_NUM, 
     SOURCE_SHIPMENT_ID, 
     SOURCE_SHIPMENT_NUM, 
     --SHIP_TO_ORGANIZATION_ID, 
     --SHIP_TO_ORGANIZATION_CODE, 
     --SHIP_TO_LOCATION_ID, 
     --SHIP_TO_LOCATION_CODE, 
 --    QUANTITY_ACCEPTED, 
 --    QUANTITY_BILLED, 
 --    QUANTITY_CANCELLED, 
 --    QUANTITY_RECEIVED, 
 --    QUANTITY_REJECTED, 
 --    NOT_TO_EXCEED_PRICE, 
 --    ALLOW_PRICE_OVERRIDE_FLAG, 
 --    PRICE_BREAK_LOOKUP_CODE, 
 --    AMOUNT, 
     CURRENCY_CODE, 
     --LAST_ACCEPT_DATE, 
     NEED_BY_DATE, 
     PROMISED_DATE, 
     --FIRM_STATUS_LOOKUP_CODE, 
     --PRICE_DISCOUNT, 
     --START_DATE, 
     --END_DATE, 
     --LEAD_TIME, 
     --LEAD_TIME_UNIT, 
     --TERMS_ID, 
     --PAYMENT_TERMS_NAME, 
     --FREIGHT_TERMS_LOOKUP_CODE, 
     --FOB_LOOKUP_CODE, 
     --SHIP_VIA_LOOKUP_CODE, 
     --ACCRUE_ON_RECEIPT_FLAG, 
     FROM_HEADER_ID, 
     FROM_LINE_ID, 
     FROM_LINE_LOCATION_ID, 
     ENCUMBERED_FLAG, 
     ENCUMBERED_DATE, 
     APPROVED_FLAG, 
     APPROVED_DATE, 
     CLOSED_CODE, 
--     SHIPMENT_STATUS, 
     --CANCEL_FLAG, 
     --CANCEL_DATE, 
--     CANCEL_REASON, 
     --CANCELLED_BY, 
     CLOSED_FLAG, 
     --CLOSED_BY, 
     --CLOSED_DATE, 
--     CLOSED_REASON, 
     --USSGL_TRANSACTION_CODE, 
     --GOVERNMENT_CONTEXT, 
     LINE_TYPE_ID, 
     LINE_TYPE
     --OUTSIDE_OPERATION_FLAG, 
     --MATCH_OPTION, 
     --OKE_CONTRACT_HEADER_ID, 
     --SECONDARY_UNIT_OF_MEASURE, 
     --SECONDARY_QUANTITY 
     FROM po_line_locations_release_v 
     WHERE po_release_id = :v_doc_hdr_id
     and :v_doc_type = 'RELEASE';
        
    SELECT 
     line_num, 
     po_line_id, 
     Item_ID, 
     Item_Number, 
     ITEM_REVISION, 
     CATEGORY_ID, 
     Item_Description ITEM_NAME, 
     (select MCA.CONCATENATED_SEGMENTS from MTL_CATEGORIES_KFV MCA where MCA.CATEGORY_ID  = pl.category_id) ITEM_CATEGORY, 
     List_price_Per_Unit, 
     Unit_Price , 
     Quantity, 
     Taxable_flag, 
     Tax_Name, 
     Closed_Code, 
     Cancel_Flag, 
     LAST_UPDATE_DATE, 
     LAST_UPDATED_BY, 
     --CREATION_DATE, 
     --CREATED_BY, 
     LINE_TYPE, 
     UNIT_MEAS_LOOKUP_CODE, 
     --QUANTITY_COMMITTED, 
     --COMMITTED_AMOUNT, 
--     ALLOW_PRICE_OVERRIDE_FLAG, 
--     NOT_TO_EXCEED_PRICE
     --UNORDERED_FLAG, 
     CLOSED_FLAG, 
     --USER_HOLD_FLAG, 
     --CANCELLED_BY, 
     --CANCEL_DATE, 
--     CANCEL_REASON, 
     --FIRM_STATUS_LOOKUP_CODE, 
     --FIRM_DATE, 
     --CONTRACT_NUM, 
     --FROM_HEADER_ID, 
     --FROM_LINE_ID, 
--     TYPE_1099, 
     --CAPITAL_EXPENSE_FLAG, 
     --CLOSED_BY, 
     --CLOSED_DATE, 
     CLOSED_CODE, 
--     CLOSED_REASON, 
     --GOVERNMENT_CONTEXT, 
     --USSGL_TRANSACTION_CODE, 
     --EXPIRATION_DATE, 
     TAX_CODE_ID, 
     BASE_UOM, 
     BASE_QTY
     --SECONDARY_UOM, 
     --SECONDARY_QTY, 
--     AUCTION_HEADER_ID, 
--     AUCTION_DISPLAY_NUMBER, 
--     AUCTION_LINE_NUMBER, 
--     BID_NUMBER, 
--     BID_LINE_NUMBER, 
--    SUPPLIER_REF_NUMBER, 
     --CONTRACT_ID, 
     --JOB_ID
     FROM po_lines_v pl
     WHERE po_header_id = :v_doc_hdr_id  
     and :v_doc_type in ('PO', 'PA');
     
    SELECT 
     REQUISITION_LINE_ID, 
     line_num, 
     line_type, 
     Item_ID, 
     Item_Description ITEM_NAME, 
     (select MCA.CONCATENATED_SEGMENTS from MTL_CATEGORIES_KFV MCA where MCA.CATEGORY_ID  = rl.category_id) ITEM_CATEGORY, 
     Quantity, 
     Unit_Meas_Lookup_Code UOM, 
     Unit_Price, 
     NEED_BY_DATE, 
     SUGGESTED_BUYER, 
     --RFQ_REQUIRED_FLAG, 
--     ON_RFQ_FLAG, 
     --CANCEL_FLAG, 
     --MODIFIED_BY_AGENT_FLAG, 
     --UN_NUMBER, 
     --HAZARD_CLASS, 
     --REFERENCE_NUM, 
     --URGENT, 
     ENCUMBERED_FLAG, 
     --DESTINATION_TYPE_CODE, 
     --SOURCE_TYPE_CODE, 
     REQUESTOR, 
     --DEST_ORGANIZATION, 
     --DELIVER_TO_LOCATION,  
    -- DEST_SUBINVENTORY, 
     --SOURCE_ORGANIZATION, 
     --SOURCE_SUBINVENTORY, 
     --OUTSIDE_OP_LINE_TYPE, 
     --DELIVER_TO_LOCATION_ID, 
--     TO_PERSON_ID, 
     CURRENCY_CODE, 
     RATE, 
     RATE_TYPE, 
     RATE_DATE, 
     CURRENCY_UNIT_PRICE, 
     SUGGESTED_BUYER_ID, 
     CLOSED_CODE, 
     CLOSED_DATE, 
     LINE_LOCATION_ID, 
     PARENT_REQ_LINE_ID, 
     PURCHASING_AGENT_ID, 
     --DOCUMENT_TYPE_CODE, 
     --BLANKET_PO_HEADER_ID, 
     --BLANKET_PO_LINE_NUM, 
--     CANCEL_REASON, 
     --CANCEL_DATE, 
--     AGENT_RETURN_NOTE, 
     --CHANGED_AFTER_RESEARCH_FLAG, 
     --VENDOR_ID, 
     --VENDOR_SITE_ID, 
     --VENDOR_CONTACT_ID, 
     --RESEARCH_AGENT_ID, 
     --ON_LINE_FLAG, 
     --WIP_ENTITY_ID, 
     --WIP_LINE_ID, 
     --WIP_REPETITIVE_SCHEDULE_ID, 
     --WIP_OPERATION_SEQ_NUM, 
     --WIP_RESOURCE_SEQ_NUM, 
     --BOM_RESOURCE_ID,  
     --USSGL_TRANSACTION_CODE, 
     --GOVERNMENT_CONTEXT, 
--     CLOSED_REASON, 
     --SOURCE_REQ_LINE_ID, 
     --DEST_ORGANIZATION_ID, 
     --SOURCE_ORGANIZATION_ID, 
     --ORDER_TYPE_LOOKUP_CODE, 
     --RATE_TYPE_DISP, 
     --SOURCE_DOCUMENT_TYPE, 
     --INVENTORY_ASSET_FLAG, 
     --INTERNAL_ORDER_ENABLED_FLAG, 
     TAX_NAME, 
     TAX_USER_OVERRIDE_FLAG, 
     TAX_CODE_ID, 
--     REQS_IN_POOL_FLAG, 
     AMOUNT
--     CURRENCY_AMOUNT, 
     --PURCHASE_BASIS, 
     --DROP_SHIP_FLAG
     FROM po_requisition_lines_v rl
     WHERE requisition_header_id = :v_doc_hdr_id
     and :v_doc_type = 'REQUISITION';
     
     
     
prompt
prompt 
prompt Document Distribution Lines
prompt ===========================
prompt


COL charge_acct format a25
col wf_item_key format a15

SELECT 
        d.po_line_id,  
        d.distribution_num,  
        d.quantity_ordered,  
        d.code_combination_id,   
        SUBSTR(RTRIM(g.segment1||'-'||g.segment2||'-'|| 
                     g.segment3||'-'||g.segment4||'-'|| 
                     g.segment5||'-'||g.segment6||'-'|| 
                     g.segment7||'-'||g.segment8||'-'|| 
                     g.segment9||'-'||g.segment10||'-'|| 
                     g.segment11||'-'||g.segment12||'-'|| 
                     g.segment13||'-'||g.segment14||'-'|| 
                     g.segment15||'-'||g.segment16||'-'|| 
                     g.segment17||'-'||g.segment18||'-'|| 
                     g.segment19||'-'||g.segment20||'-'|| 
                     g.segment21||'-'||g.segment22||'-'|| 
                     g.segment23||'-'||g.segment24||'-'|| 
                     g.segment25||'-'||g.segment26||'-'|| 
                     g.segment27||'-'||g.segment28||'-'|| 
                     g.segment29||'-'||g.segment30,'-')
    ,1,100) charge_acct, 
     --CREATION_DATE, 
     --CREATED_BY, 
     PO_RELEASE_ID, 
     QUANTITY_DELIVERED, 
     QUANTITY_BILLED, 
     QUANTITY_CANCELLED, 
     --REQ_HEADER_REFERENCE_NUM, 
    -- REQ_LINE_REFERENCE_NUM, 
     --REQ_DISTRIBUTION_ID, 
     --DELIVER_TO_LOCATION_ID, 
     --DELIVER_TO_PERSON_ID, 
     RATE_DATE, 
     RATE, 
     AMOUNT_BILLED, 
     ACCRUED_FLAG, 
     ENCUMBERED_FLAG, 
     ENCUMBERED_AMOUNT, 
     UNENCUMBERED_QUANTITY, 
     UNENCUMBERED_AMOUNT, 
     FAILED_FUNDS_LOOKUP_CODE, 
     --GL_ENCUMBERED_DATE, 
     --GL_ENCUMBERED_PERIOD_NAME, 
     --GL_CANCELLED_DATE, 
     --DESTINATION_TYPE_CODE, 
     --DESTINATION_ORGANIZATION_ID, 
     --DESTINATION_SUBINVENTORY, 
     BUDGET_ACCOUNT_ID, 
     --ACCRUAL_ACCOUNT_ID, 
     --VARIANCE_ACCOUNT_ID, 
     --PREVENT_ENCUMBRANCE_FLAG, 
     --USSGL_TRANSACTION_CODE, 
     --GOVERNMENT_CONTEXT, 
     --DESTINATION_CONTEXT,  
     --SOURCE_DISTRIBUTION_ID, 
     --PROJECT_ID, 
     --TASK_ID, 
     --EXPENDITURE_TYPE, 
     --PROJECT_ACCOUNTING_CONTEXT, 
     --EXPENDITURE_ORGANIZATION_ID, 
     --GL_CLOSED_DATE,  
     --ACCRUE_ON_RECEIPT_FLAG, 
     --EXPENDITURE_ITEM_DATE, 
--     MRC_RATE_DATE, 
--     MRC_RATE, 
--     MRC_ENCUMBERED_AMOUNT, 
--     MRC_UNENCUMBERED_AMOUNT, 
--     END_ITEM_UNIT_NUMBER, 
     TAX_RECOVERY_OVERRIDE_FLAG, 
     RECOVERABLE_TAX, 
     NONRECOVERABLE_TAX, 
     RECOVERY_RATE, 
     --OKE_CONTRACT_LINE_ID, 
     --OKE_CONTRACT_DELIVERABLE_ID, 
     AMOUNT_ORDERED, 
     AMOUNT_DELIVERED, 
     AMOUNT_CANCELLED, 
     DISTRIBUTION_TYPE, 
     AMOUNT_TO_ENCUMBER, 
     --INVOICE_ADJUSTMENT_FLAG, 
     --DEST_CHARGE_ACCOUNT_ID, 
     --DEST_VARIANCE_ACCOUNT_ID, 
     WF_ITEM_KEY
--     QUANTITY_FINANCED, 
--     AMOUNT_FINANCED, 
--     QUANTITY_RECOUPED, 
--     AMOUNT_RECOUPED,  
--     RETAINAGE_WITHHELD_AMOUNT, 
--     RETAINAGE_RELEASED_AMOUNT, 
--     INVOICED_VAL_IN_NTFN, 
--     TAX_ATTRIBUTE_UPDATE_CODE, 
--     INTERFACE_DISTRIBUTION_REF 
     FROM  po_distributions_all d, gl_code_combinations g  
     WHERE d.po_line_id in (select pla.po_line_id  
                                      from po_lines_all pla,  po_headers_all pha  
                                      where pla.po_header_id = pha.po_header_id  
                                        and pha.po_header_id = :v_doc_hdr_id)  
    AND d.code_combination_id = g.code_combination_id(+) 
    and :v_doc_type = 'PO'
    ORDER BY d.po_line_id, d.distribution_num ;        
        
    SELECT 
        d.requisition_line_id,  
        d.distribution_num,  
        d.req_line_quantity,  
        d.code_combination_id,   
        SUBSTR(RTRIM(g.segment1||'-'||g.segment2||'-'|| 
                     g.segment3||'-'||g.segment4||'-'|| 
                     g.segment5||'-'||g.segment6||'-'|| 
                     g.segment7||'-'||g.segment8||'-'|| 
                     g.segment9||'-'||g.segment10||'-'|| 
                     g.segment11||'-'||g.segment12||'-'|| 
                     g.segment13||'-'||g.segment14||'-'|| 
                     g.segment15||'-'||g.segment16||'-'|| 
                     g.segment17||'-'||g.segment18||'-'|| 
                     g.segment19||'-'||g.segment20||'-'|| 
                     g.segment21||'-'||g.segment22||'-'|| 
                     g.segment23||'-'||g.segment24||'-'|| 
                     g.segment25||'-'||g.segment26||'-'|| 
                     g.segment27||'-'||g.segment28||'-'|| 
                     g.segment29||'-'||g.segment30,'-') 
       ,1,100) charge_acct, 
        d.encumbered_flag, 
     GL_ENCUMBERED_DATE, 
     GL_ENCUMBERED_PERIOD_NAME, 
     GL_CANCELLED_DATE, 
     --FAILED_FUNDS_LOOKUP_CODE, 
     ENCUMBERED_AMOUNT, 
     BUDGET_ACCOUNT_ID
     --ACCRUAL_ACCOUNT_ID, 
     --VARIANCE_ACCOUNT_ID, 
     --PREVENT_ENCUMBRANCE_FLAG, 
     --USSGL_TRANSACTION_CODE, 
     --GOVERNMENT_CONTEXT, 
     --PROJECT_ID, 
     --TASK_ID, 
     --EXPENDITURE_TYPE, 
     --PROJECT_ACCOUNTING_CONTEXT, 
     --EXPENDITURE_ORGANIZATION_ID, 
     --GL_CLOSED_DATE, 
     --SOURCE_REQ_DISTRIBUTION_ID, 
     --ALLOCATION_TYPE, 
     --ALLOCATION_VALUE, 
     --PROJECT_RELATED_FLAG, 
     --EXPENDITURE_ITEM_DATE  
    FROM  po_req_distributions_all d,  gl_code_combinations g  
    WHERE d.requisition_line_id in (select pla.requisition_line_id  
                                      from po_requisition_lines_all pla,  
                                           po_requisition_headers_all pha  
                                      where pla.requisition_header_id =  
                                            pha.requisition_header_id  
                                        and pha.requisition_header_id = :v_doc_hdr_id)  
    AND d.code_combination_id = g.code_combination_id(+) 
    and :v_doc_type = 'REQUISITION'
    ORDER BY d.requisition_line_id, d.distribution_num ;  
  
    SELECT 
    d.po_line_id,  
        d.distribution_num,  
        d.quantity_ordered,  
        d.code_combination_id,   
        SUBSTR(RTRIM(g.segment1||'-'||g.segment2||'-'|| 
                     g.segment3||'-'||g.segment4||'-'|| 
                     g.segment5||'-'||g.segment6||'-'|| 
                     g.segment7||'-'||g.segment8||'-'|| 
                     g.segment9||'-'||g.segment10||'-'|| 
                     g.segment11||'-'||g.segment12||'-'|| 
                     g.segment13||'-'||g.segment14||'-'|| 
                     g.segment15||'-'||g.segment16||'-'|| 
                     g.segment17||'-'||g.segment18||'-'|| 
                     g.segment19||'-'||g.segment20||'-'|| 
                     g.segment21||'-'||g.segment22||'-'|| 
                     g.segment23||'-'||g.segment24||'-'|| 
                     g.segment25||'-'||g.segment26||'-'|| 
                     g.segment27||'-'||g.segment28||'-'|| 
                     g.segment29||'-'||g.segment30,'-')
               ,1,100) charge_acct,  
     CREATION_DATE, 
     CREATED_BY, 
     PO_RELEASE_ID, 
     QUANTITY_DELIVERED, 
     QUANTITY_BILLED, 
     QUANTITY_CANCELLED, 
     REQ_HEADER_REFERENCE_NUM, 
     REQ_LINE_REFERENCE_NUM, 
     REQ_DISTRIBUTION_ID, 
     --DELIVER_TO_LOCATION_ID, 
     --DELIVER_TO_PERSON_ID, 
     RATE_DATE, 
     RATE, 
     AMOUNT_BILLED, 
     --ACCRUED_FLAG, 
     ENCUMBERED_FLAG, 
     ENCUMBERED_AMOUNT, 
     --UNENCUMBERED_QUANTITY, 
     --UNENCUMBERED_AMOUNT, 
     --FAILED_FUNDS_LOOKUP_CODE, 
     --GL_ENCUMBERED_DATE, 
     --GL_ENCUMBERED_PERIOD_NAME, 
     --GL_CANCELLED_DATE, 
     --DESTINATION_TYPE_CODE, 
     --DESTINATION_ORGANIZATION_ID, 
     --DESTINATION_SUBINVENTORY, 
     BUDGET_ACCOUNT_ID, 
     --ACCRUAL_ACCOUNT_ID, 
     --VARIANCE_ACCOUNT_ID, 
     --PREVENT_ENCUMBRANCE_FLAG, 
     --USSGL_TRANSACTION_CODE, 
     --GOVERNMENT_CONTEXT, 
    -- DESTINATION_CONTEXT,  
    -- SOURCE_DISTRIBUTION_ID, 
    -- PROJECT_ID, 
     --TASK_ID, 
     --EXPENDITURE_TYPE, 
    -- PROJECT_ACCOUNTING_CONTEXT, 
    -- EXPENDITURE_ORGANIZATION_ID, 
    -- GL_CLOSED_DATE,  
    -- ACCRUE_ON_RECEIPT_FLAG, 
    -- EXPENDITURE_ITEM_DATE, 
    -- MRC_RATE_DATE, 
    -- MRC_RATE, 
    -- MRC_ENCUMBERED_AMOUNT, 
     --MRC_UNENCUMBERED_AMOUNT, 
     --END_ITEM_UNIT_NUMBER, 
     TAX_RECOVERY_OVERRIDE_FLAG, 
     RECOVERABLE_TAX, 
     NONRECOVERABLE_TAX, 
     RECOVERY_RATE, 
    -- OKE_CONTRACT_LINE_ID, 
     --OKE_CONTRACT_DELIVERABLE_ID, 
     AMOUNT_ORDERED, 
     AMOUNT_DELIVERED, 
     AMOUNT_CANCELLED, 
     DISTRIBUTION_TYPE, 
     --AMOUNT_TO_ENCUMBER, 
     --INVOICE_ADJUSTMENT_FLAG, 
     --DEST_CHARGE_ACCOUNT_ID, 
     --DEST_VARIANCE_ACCOUNT_ID, 
     QUANTITY_FINANCED, 
     AMOUNT_FINANCED, 
     QUANTITY_RECOUPED, 
     AMOUNT_RECOUPED,  
     RETAINAGE_WITHHELD_AMOUNT, 
     RETAINAGE_RELEASED_AMOUNT, 
     WF_ITEM_KEY 
     --INVOICED_VAL_IN_NTFN, 
     --TAX_ATTRIBUTE_UPDATE_CODE, 
     --INTERFACE_DISTRIBUTION_REF        
     FROM  po_distributions_all d,  gl_code_combinations g  
     WHERE d.po_release_id = :v_doc_hdr_id  
     AND d.code_combination_id = g.code_combination_id(+) 
     and :v_doc_type = 'RELEASE'
     ORDER BY d.po_line_id, d.distribution_num;
     
--> TO Check Releases query 


prompt
prompt 


Prompt Preparer Information
prompt ====================
prompt 

-- Derive Employee ID 
begin
   begin
    select employee_id 
    into :v_employee_id
    from po_action_history 
    where object_id = :v_doc_hdr_id 
    and object_type_code = :v_doc_type
    and action_code = 'SUBMIT'
    and sequence_num = (select max(sequence_num) from  po_action_history where object_id = :v_doc_hdr_id
                       and object_type_code = :v_doc_type
                       and action_code = 'SUBMIT') ;
    :v_emp_derived_from := 'Employee derived from submitter';
    
   EXCEPTION
     when NO_DATA_FOUND then
         -- do nothing. Document has not been submitted for approval
         :v_employee_id := null;
   end;
   
   if :v_employee_id is null then
   begin
     if :v_doc_type = 'PO' then   
        SELECT employee_id into :v_employee_id
        from fnd_user  
        where user_id = (select created_by from po_headers where po_header_id = :v_doc_hdr_id);
    elsif :v_doc_type = 'REQUISITION' then 
       SELECT preparer_id into :v_employee_id
       from PO_REQUISITION_HEADERS  
       where requisition_header_id = :v_doc_hdr_id;
    else
       SELECT employee_id into :v_employee_id 
       from fnd_user  
       where user_id = (select created_by from po_releases where po_release_id = :v_doc_hdr_id);
    end if;  
    :v_emp_derived_from := 'Employee derived from document creator';
    
   EXCEPTION
     when NO_DATA_FOUND then
         -- do nothing. Document has not been submitted for approval
         dbms_output.put_line('ERROR: Could not determine employee ID for document approver');
         dbms_output.put_line('ACTION: Please contact Oracle Support to verify this issue');
   end;
   end if; 
End;
/


COL EMPLOYEE_DERIVED_FROM format a40
COL EMPLOYEE_NAME format a30
col FND_EMAIL  format a30


SELECT :v_emp_derived_from EMPLOYEE_DERIVED_FROM, fu.employee_id EMPLOYEE_ID, 
       (select full_name from per_all_people_f per where per.person_id = fu.employee_id and  rownum = 1)  EMPLOYEE_NAME, 
       fu.user_id, fu.user_name FND_USER_NAME, fu.email_address FND_EMAIL,
       fu.start_date FND_START_DATE, fu.end_date FND_END_DATE 
FROM fnd_user fu  
WHERE employee_id = :v_employee_id 
AND sysdate between fu.start_date and nvl(fu.end_date, to_date('30-DEC-3012', 'DD-MON-YYYY'));




-- Collect preparer relevant information

declare 
   cursor C1 is 
     SELECT pos.position_id, pos.name Position,job.job_id,   
      job.name Job, loc.location_code, 
      pa.business_group_id,  
      pa.supervisor_id, fu.user_name  
      FROM per_all_assignments_f pa,  
      per_positions pos,  
      per_jobs job,  
      po_locations_val_v loc,  
      fnd_user fu  
      WHERE pa.person_id = fu.employee_id  
      AND fu.employee_id = :v_employee_id
      AND pa.position_id =  pos.position_id(+)  
      AND pa.job_id = job.job_id(+)  
      AND sysdate between pa.effective_start_date and NVL(pa.effective_end_date,sysdate+1)  
      AND pa.primary_flag = 'Y'  
      and pa.LOCATION_ID = loc.LOCATION_ID(+)  
      and pa.assignment_type in ('E','C');

--alternate query in case the employee is terminated
   cursor C2 is 
     SELECT 
     employee_id,   
     pos.position_id, pos.name Position,job.job_id,  
     job.name Job, loc.location_code,  
     pa.business_group_id,  
     pa.supervisor_id, fu.user_name  
     FROM per_all_assignments_f pa,  
     per_positions pos,  
     per_jobs job,  
     po_locations_val_v loc,  
     fnd_user fu  
     WHERE pa.person_id = fu.employee_id  
     AND fu.employee_id = :v_employee_id 
     and pa.effective_end_date = (select max(effective_end_date) from per_all_assignments_f pa where assignment_type in ('E' , 'C')  and person_id = fu.employee_id)  
     AND pa.position_id =  pos.position_id(+)  
     AND pa.job_id = job.job_id(+)  
     AND pa.primary_flag = 'Y'  
     and pa.LOCATION_ID = loc.LOCATION_ID(+)  
     and pa.assignment_type in ('E','C')  
     and rownum = 1;

   cursor C3(person_id number) is 
      SELECT 
         per.full_name supervisor, 
         per.effective_start_date, 
         per.effective_end_date, 
         per.start_date 
         FROM per_all_people_f per 
         WHERE per.person_id = person_id
         and (SYSDATE between NVL(per.EFFECTIVE_START_DATE,SYSDATE) and NVL(per.EFFECTIVE_END_DATE,SYSDATE+1)) ;
         
begin
   for i in C1 loop
         :v_prp_position_id     := i.position_id;
         :v_prp_position        := i.Position;
         :v_prp_job_id          := i.job_id;
         :v_prp_job_name        := i.job;
         :v_prp_location_code   := i.location_code;
         :v_prp_business_group_id := i.business_group_id;
         :v_prp_supervisor_id   := i.supervisor_id;
         :v_prp_user_name       := i.user_name;
   end loop;
   if :v_prp_position_id is null and :v_prp_job_id is null then
      for i in C2 loop
         :v_prp_position_id     := i.position_id;
         :v_prp_position        := i.Position;
         :v_prp_job_id          := i.job_id;
         :v_prp_job_name        := i.job;
         :v_prp_location_code   := i.location_code;
         :v_prp_business_group_id := i.business_group_id;
         :v_prp_supervisor_id   := i.supervisor_id;
         :v_prp_user_name       := i.user_name;
      end loop;
   end if;
   if :v_prp_position_id is null and :v_prp_job_id is null then
       dbms_output.put_line('ERROR: Could not find active employee for person id: '|| :v_employee_id);
       dbms_output.put_line('Please verify there is a valid FND application user name and employee record for the preparer');
   end if;
 
   /*
   -- collect supervisor information
    for j in C3(:v_supervisor_id) loop   
       :v_supervisor_name
       v_eff_start_date
       v_eff_end_date
    end loop;
    
    */
    
end;
/

prompt
prompt
prompt Approver List 
prompt ==============
prompt 

declare
My_Error EXCEPTION;
l_counter number;
l_counter2 number;

cursor C1(person_id number) is 
     SELECT PERSON_ID, EMPLOYEE_NAME, SUPERVISOR_ID, SUPERVISOR_NAME,  decode(CONNECT_BY_ISCYCLE, 0, 'No', 'Yes') IS_LOOPING  
      FROM   
      (SELECT pafe.person_id PERSON_ID, pafe.supervisor_id SUPERVISOR_ID,   
        (select ppfs2.full_name from Per_All_People_f  ppfs2 where ppfs2.person_id = pafe.supervisor_id and sysdate between ppfs2.effective_start_date and ppfs2.effective_end_date) Supervisor_name,  
        ppfs.full_name  Employee_Name  
      FROM Per_All_Assignments_f pafe,  
      Per_All_People_f ppfs,  
      Per_All_Assignments_f pafs,  
      per_person_types_v ppts,  
      per_person_type_usages_f pptu  
      WHERE pafe.business_group_id = :v_prp_business_group_id
      AND Trunc(SYSDATE) BETWEEN pafe.Effective_Start_Date  
      AND pafe.Effective_End_Date  
      AND pafe.Primary_Flag = 'Y'  
      AND pafe.Assignment_Type IN ('E','C')  
      AND ppfs.Person_Id = pafe.person_Id  
      AND Trunc(SYSDATE) BETWEEN ppfs.Effective_Start_Date  
      AND ppfs.Effective_End_Date  
      AND pafs.Person_Id = ppfs.Person_Id  
      AND Trunc(SYSDATE) BETWEEN pafs.Effective_Start_Date  
      AND pafs.Effective_End_Date  
      AND pafs.Primary_Flag = 'Y'  
      AND pafs.Assignment_Type IN ('E','C')  
      AND pptu.Person_Id = ppfs.Person_Id  
      AND ppts.person_type_id = pptu.person_type_id  
      AND ppts.System_Person_Type IN ('EMP','EMP_APL','CWK')) tl 
      CONNECT BY nocycle tl.person_id = PRIOR tl.supervisor_id  
      START WITH  tl.person_id = person_id;
     
cursor C2(emp_id number) is 
     SELECT job.job_id, job.name  
      FROM per_all_assignments_f pa,  
      per_positions pos,  
      per_jobs job,  
      per_all_people_f per,  
      po_locations_val_v loc,  
      fnd_user fu  
      WHERE pa.person_id = fu.employee_id  
      AND fu.employee_id = emp_id  
      AND pa.position_id =  pos.position_id(+)  
      AND pa.job_id = job.job_id(+)  
      AND sysdate between pa.effective_start_date and NVL(pa.effective_end_date,sysdate+1)  
      AND pa.primary_flag = 'Y'  
      AND pa.supervisor_id = per.person_id(+)  
      and (SYSDATE between NVL(per.EFFECTIVE_START_DATE,SYSDATE) and NVL(per.EFFECTIVE_END_DATE,SYSDATE+1))  
      and pa.LOCATION_ID = loc.LOCATION_ID(+)  
      and pa.assignment_type in ('E','C');
     
                                                                                             
                                                                                             
Cursor D1(emp_id number) is 
     SELECT * FROM 
     (SELECT /*+ LEADING(POEH) */POEH.superior_id SUP_ID, 
      poeh.superior_level SUP_LEVEL, 
      HREC.full_name SUPERIOR_NAME  
      FROM PO_EMPLOYEES_CURRENT_X HREC,  
      PO_EMPLOYEE_HIERARCHIES POEH  
      WHERE POEH.position_structure_id = :v_apprv_path_id 
      AND POEH.employee_id = emp_id 
      AND HREC.employee_id = POEH.superior_id  
      AND POEH.superior_level > 0  
      UNION ALL  
      SELECT /*+ LEADING(POEH) */ poeh.superior_id SUP_ID,
      poeh.superior_level SUP_LEVEL, 
      cwk.full_name SUPERIOR_NAME 
      FROM PO_WORKFORCE_CURRENT_X cwk,  
      PO_EMPLOYEE_HIERARCHIES POEH  
      WHERE poeh.position_structure_id = :v_apprv_path_id 
      AND poeh.employee_id = emp_id
      AND cwk.person_id = POEH.superior_id  
      AND poeh.superior_level > 0  
      AND nvl(fnd_profile.value('HR_TREAT_CWK_AS_EMP'),'N') = 'Y'  
      ORDER BY sup_level, superior_name) tl;

cursor D2(Emp_ID number) is 
SELECT pos.position_id, pos.name  
      FROM per_all_assignments_f pa,  
      per_positions pos,  
      per_jobs job,  
      per_all_people_f per,  
      po_locations_val_v loc,  
      fnd_user fu  
      WHERE pa.person_id = fu.employee_id  
      AND fu.employee_id = Emp_ID  
      AND pa.position_id =  pos.position_id(+)  
      AND pa.job_id = job.job_id(+)  
      AND sysdate between pa.effective_start_date and NVL(pa.effective_end_date,sysdate+1)  
      AND pa.primary_flag = 'Y'  
      AND pa.supervisor_id = per.person_id(+)  
      and (SYSDATE between NVL(per.EFFECTIVE_START_DATE,SYSDATE) and NVL(per.EFFECTIVE_END_DATE,SYSDATE+1))  
      and pa.LOCATION_ID = loc.LOCATION_ID(+)  
      and pa.assignment_type in ('E','C');
     
cursor CHK1(emp_id number) is
SELECT fu.employee_id, fu.user_id, fu.user_name , fu.email_address, fu.start_date , fu.end_date  
     FROM fnd_user fu  
     WHERE employee_id = emp_id
     AND sysdate between fu.start_date and nvl(fu.end_date, to_date('31-dec-4012', 'DD-MON-RRRR'));

Cursor CHK2(per_id number) is
SELECT pos.name , pos.position_id, pa.effective_start_date, pa.effective_end_date, decode(assignment_type, 'E', 'Employee', assignment_type) Assigment_Type  
      FROM per_all_assignments_f pa,  
      per_positions pos  
      where pa.person_id =  per_id  
      and pa.assignment_type in ('E','C')  
      AND sysdate between pa.effective_start_date and NVL(pa.effective_end_date,sysdate+1)
      AND pa.position_id =  pos.position_id(+)
      AND rownum = 1;
     
Cursor CHK3(emp_id number) is
     SELECT Name, Display_name, notification_preference, email_address, status, start_date, expiration_date   
      FROM wf_users   
      WHERE orig_system_id = emp_id 
      AND orig_system = 'PER'  
      AND status = 'ACTIVE';
      
Cursor CHK4(per_id number) is
SELECT person_id, full_name, effective_start_date, effective_end_date, start_date, business_group_id, employee_number  
      FROM per_people_f  
      WHERE person_id = per_id
      AND sysdate between effective_start_date and effective_end_date;
      


Cursor ASGN(posit_id number) is
SELECT cf.CONTROL_FUNCTION_NAME ,  
      ag.CONTROL_GROUP_NAME ,  
      cr.RULE_TYPE_CODE ,  
      cr.OBJECT_CODE ,  
      to_char(cr.AMOUNT_LIMIT) Amount_Limit,  
      (cr.segment1_low||'.'||  
      cr.segment2_low||'.'||  
      cr.segment3_low||'.'||  
      cr.segment4_low||'.'||  
      cr.segment5_low||'.'||  
      cr.segment6_low||'.'||  
      cr.segment7_low||'.'||  
      cr.segment8_low||'.'||  
      cr.segment9_low||'.'||  
      cr.segment10_low||'.'||  
      cr.segment11_low||'.'||  
      cr.segment12_low) Account_Range_Low,  
      (cr.segment1_high||'.'||  
      cr.segment2_high||'.'||  
      cr.segment3_high||'.'||  
      cr.segment4_high||'.'||  
      cr.segment5_high||'.'||  
      cr.segment6_high||'.'||  
      cr.segment7_high||'.'||  
      cr.segment8_high||'.'||  
      cr.segment9_high||'.'||  
      cr.segment10_high||'.'||  
      cr.segment11_high||'.'||  
      cr.segment12_high) Account_Range_High  
      FROM  
      PO_POSITION_CONTROLS_ALL a,  
      po_CONTROL_GROUPS ag,  
      po_CONTROL_functions cf,  
      PO_CONTROL_RULES cr  
      WHERE  
      a.CONTROL_GROUP_ID = ag.CONTROL_GROUP_ID and  
      a.CONTROL_FUNCTION_ID = cf.CONTROL_FUNCTION_ID and  
      cf.DOCUMENT_TYPE_CODE = :v_doc_type and  
      cf.DOCUMENT_SUBTYPE = :v_doc_subtype and  
      a.POSITION_ID = posit_id and  
      (SYSDATE BETWEEN a.START_DATE AND nvl(a.END_DATE,SYSDATE+1)) and  
      cr.CONTROL_GROUP_ID = a.CONTROL_GROUP_ID and  
      ('' is null or cr.OBJECT_CODE in (select lookup_code  
      from po_lookup_codes  
      where lookup_type = 'CONTROLLED_OBJECT' and displayed_field like '')) and  
      cf.ENABLED_FLAG = 'Y' and  
      ag.ENABLED_FLAG = 'Y'  
      ORDER BY  
      a.CONTROL_FUNCTION_ID,  
      a.CONTROL_GROUP_ID,  
      cr.OBJECT_CODE,  
      cr.RULE_TYPE_CODE DESC;

Cursor ASGN2(job number) is
     SELECT  a.org_id, cf.CONTROL_FUNCTION_NAME ,ag.CONTROL_GROUP_NAME ,  
      cr.RULE_TYPE_CODE,cr.OBJECT_CODE ,  
      to_char(cr.AMOUNT_LIMIT) Amount_Limit,  
      (cr.segment1_low||'.'||cr.segment2_low||'.'||  
       cr.segment3_low||'.'||cr.segment4_low||'.'||  
       cr.segment5_low||'.'||cr.segment6_low||'.'||  
       cr.segment7_low||'.'||cr.segment8_low||'.'||  
       cr.segment9_low||'.'||cr.segment10_low||'.'||  
       cr.segment11_low||'.'||cr.segment12_low) Account_Range_Low,  
      (cr.segment1_high||'.'||cr.segment2_high||'.'||  
       cr.segment3_high||'.'||cr.segment4_high||'.'||  
       cr.segment5_high||'.'||cr.segment6_high||'.'||  
       cr.segment7_high||'.'||cr.segment8_high||'.'||  
       cr.segment9_high||'.'||cr.segment10_high||'.'||  
       cr.segment11_high||'.'||cr.segment12_high) Account_Range_High 
      FROM  
      PO_POSITION_CONTROLS a, po_CONTROL_GROUPS ag,  
      po_CONTROL_functions cf, PO_CONTROL_RULES cr  
      WHERE  
      a.CONTROL_GROUP_ID = ag.CONTROL_GROUP_ID and  
      a.CONTROL_FUNCTION_ID = cf.CONTROL_FUNCTION_ID and  
      a.JOB_ID = job and  
      cf.DOCUMENT_TYPE_CODE = :v_doc_type and  
      cf.DOCUMENT_SUBTYPE = :v_doc_subtype and  
      (SYSDATE BETWEEN a.START_DATE AND nvl(a.END_DATE,SYSDATE+1)) and  
      cr.CONTROL_GROUP_ID = a.CONTROL_GROUP_ID and  
      ('' is null or cr.OBJECT_CODE in (select lookup_code  
                                        from po_lookup_codes  
                                          where lookup_type = 'CONTROLLED_OBJECT' and displayed_field like '')) and  
      cf.ENABLED_FLAG = 'Y' and  
      ag.ENABLED_FLAG = 'Y'  
      ORDER BY  
      a.CONTROL_FUNCTION_ID,  
        a.CONTROL_GROUP_ID,  
        cr.OBJECT_CODE,  
        cr.RULE_TYPE_CODE DESC;
     
     
Begin

   if (:v_approval_method = 'SUPERVISOR') then  --Emp/supervisor Hierarchy
      dbms_output.put_line('Employee Supervisor Hierarchy');
      dbms_output.put_line('==============================');
      for i in C1(:v_employee_id) loop
         for j in C2(i.person_id) loop
            :v_job_id := j.job_id;
            :v_job_name := j.name;
         end loop;
         dbms_output.put_line('.');
         dbms_output.put_line('****************************************************************************************************************************************************');
         dbms_output.put_line('Employee Name is '||i.employee_name||', employee ID '||i.person_id||', Job is '|| :v_job_name ||', Job ID is '|| :v_job_id ||'. Supervisor name is '||i.supervisor_name||', supervisor id is '||i.supervisor_id );
         -- Check for looping 
         if i.is_looping = 'YES' then
            dbms_output.put_line('Warning: Circular hierarchy is present for employee '||i.supervisor_name);
            dbms_output.put_line('Action: Ensure that there is a user in the hierarchy with enough limits to approve the document to prevent the workflow to fail when building the approvers list');
         end if;
            
         dbms_output.put_line('* Checks for this employee '); 
         dbms_output.put_line('.');
         dbms_output.put_line('  FND User Validation (FND_USERS)');
         l_counter2 := 0;
         for j in CHK1(i.person_id) loop
                 dbms_output.put_line('   FND User ID: '||j.user_id||', FND Username: '||j.user_name||', e-mail address: '||j.email_address||', Start Date: '||j.start_date||', End Date: '|| j.end_date);
                 l_counter2 := l_counter2 + 1;
         end loop;
         if l_counter2 > 1 then
                  dbms_output.put_line('Warning: This employee has multiple user names.');
                  dbms_output.put_line('Action: Please ensure the employee is associated to only one application user: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is: System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Use the employee name to find the user record');
                  dbms_output.put_line('        c. Do changes to ensure that only one user is associated to the employee');
                  dbms_output.put_line('        d. Save changes');
         elsif l_counter2 = 0 then
                  dbms_output.put_line('Warning: This employee is not assigned to any active FND user.');
                  dbms_output.put_line('Action: Please make sure employee is assigned to a valid FND user and verify the start and end dates include today: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is: System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Use the employee name to find the user record');
                  dbms_output.put_line('        c. Verify that user is not end dated (null effective end date or later than current date). The user will be automatically end-dated when password expires depending on the password expiration settings defined in the Define Users form.');
                  dbms_output.put_line('        d. Save changes');
         end if;
         
         dbms_output.put_line('.');
         dbms_output.put_line('  WF User Validation (WF_USERS)');
         l_counter2 := 0;
         for j in CHK3(i.person_id) loop
                 dbms_output.put_line('    Name: '||j.name||', Display Name: '||j.display_name||', Status: '||j.status||', E-mail Address: '||j.email_address||', Start Date: '||j.start_date||', Expiration Date: '||j.expiration_date);
                 l_counter2 := l_counter2 + 1;
         end loop;
         if l_counter2 = 0 then
                  dbms_output.put_line('Warning: Username does not exist in the workflow tables.');
                  dbms_output.put_line('Action: Follow these steps to synchronize the user: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is : System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Query user');
                  dbms_output.put_line('        c. Remove values from person name and email address and save changes');
                  dbms_output.put_line('        d. Re-Query user');
                  dbms_output.put_line('        e. Re-add the data in the person region and save the changes.');
         end if;
              
         dbms_output.put_line('.');
         dbms_output.put_line('  Employee Dates Validation (PER_PEOPLE)');
         l_counter2 := 0;
         for j in CHK4(i.person_id) loop
                 dbms_output.put_line('    Person ID: '||j.person_id||', Full Name: '||j.full_name||', Business Group ID: '||j.business_group_id||', Employee Number: '||j.employee_number||', Start Date: '||j.effective_start_date||', End Date: '||j.effective_end_date);
                 l_counter2 := l_counter2 + 1;
         end loop;
         if l_counter2 = 0 then
                  dbms_output.put_line('Warning: Username associated to a terminated employee.');
                  dbms_output.put_line('Action: Remove all references to this employee in the hierarchy using the assignment section in the People Define form: ');
                  dbms_output.put_line('        a. Navigation if HR is fully installed: HR Responsibility > People > Enter and Maintain. ');
                  dbms_output.put_line('        b. Navigation if HR is shared: Purchasing Responsibility > Setup > Personnel > Employees  ');
                  dbms_output.put_line('        c. Remove values from person name and email address and save changes');
                  dbms_output.put_line('        d. Re-Query user');
                  dbms_output.put_line('        e. Re-add the data in the person region and save the changes.');
         end if;
             
         dbms_output.put_line('.');
         dbms_output.put_line('  Assignments For Position Hierarchy ');
         l_counter2 := 0;
         dbms_output.put_line('.');
         dbms_output.put_line('   DOCUMENT TYPE                        APPRV GROUP NAME      RULE             RULE TYPE             AMOUNT LIMIT          ACCOUNT RANGE LOW               ACCOUNT RANGE HIGH  ');
         dbms_output.put_line('   ===================================  ====================  ===============  ====================  ====================  ==============================  ==============================');
         dbms_output.put_line('.');
         for j in ASGN(:v_job_id) loop
                 dbms_output.put_line('   '||rpad(j.control_function_name, 35)||'  '||rpad(j.control_group_name, 20)||'  '||rpad(j.rule_type_code,15)||'  '||rpad(j.OBJECT_CODE, 20)||'  '||rpad(j.amount_limit,20)||'  '||rpad(j.account_range_low,30)||'  '||rpad(j.account_range_high,30));
                 --dbms_output.put_line('-- '||substr(1,23, i.control_function_name)||'  '||substr(1,20, i.control_group_name)||'  '||substr(1,15, i.rule_type_code)||'  '||substr(1,20, i.OBJECT_CODE)||'  '||substr(1,20, 'i.amount_limit')||'  '||substr(1, 40, i.account_range_low)||'  '||substr(1,40,i.account_range_high));
                 l_counter2 := l_counter2 + 1;
         end loop;
         if l_counter2 = 0 then
                  dbms_output.put_line('Warning: No Approval Assignments found for this document type and position.');
                  dbms_output.put_line('Action: Assign an approval group to this document type and position if needed. Navigation is: PO Responsibility > Setup > Approvals > Approval Assignments.');
         end if;
         
         dbms_output.put_line('.');
         dbms_output.put_line('.');
                         
         dbms_output.put_line ('  Verify Approval Authority'); 
         PO_DOCUMENT_ACTION_PVT.VERIFY_AUTHORITY( 
                                      P_DOCUMENT_ID      => :v_doc_hdr_id , 
                                      P_DOCUMENT_TYPE    => :v_doc_type, 
                                      P_DOCUMENT_SUBTYPE => :v_doc_subtype, 
                                      P_EMPLOYEE_ID      => i.person_id, 
                                      X_RETURN_STATUS    => :v_ret_status, 
                                      X_RETURN_CODE      => :v_ret_code, 
                                      X_EXCEPTION_MSG    => :v_exception_msg, 
                                      X_AUTH_FAILED_MSG  => :v_auth_fail_msg);

         if (:v_ret_status = 'S') then
                 if (:v_ret_code is null) then
                    dbms_output.put_line('Test Successful. Employee id: '||i.person_id||' has authority to approve this document');
                 else 
                    dbms_output.put_line('Test Failed. Employee id: '||i.person_id||' has no authority to approve this document');
                    dbms_output.put_line('Authorization Failure Messages is: '||substr(:v_auth_fail_msg, 1, 180));
                 end if;
         else
                 dbms_output.put_line('Error: Test execution of PO_DOCUMENT_ACTION_PVT.VERIFY_AUTHORITY failed');
                 dbms_output.put_line('       Exception Message: '||substr(:v_exception_msg,1,100));
                 dbms_output.put_line('       Authorization Failed Message: '||substr(:v_auth_fail_msg,1,180) );
         end if;

         dbms_output.put_line('* Checks for this employee completed!'); 
         --dbms_output.put_line('.');

      end loop;
   else -- job/position hierarchy
       dbms_output.put_line('Position Hierarchy');
       dbms_output.put_line('====================');
       if :v_apprv_path_id is null then
          dbms_output.put_line('Error: No default approval path found in the document type, or in previous document submit actions');
          dbms_output.put_line('       Approval position hierarchy requires an approval path. Make sure the document type has a default approval path.');
          dbms_output.put_line('       a. Go to the document types form. Navigation: PO Responsibility > Setup > Purchasing > Document types');
          dbms_output.put_line('       b. Query the specific document type i.e. Purchase Order');
          dbms_output.put_line('       c. Associate a default hierarchy.');
          raise My_Error;       
        end if;
        
        select name into :v_apprv_hierarchy
        from PER_POSITION_STRUCTURES 
        WHERE POSITION_STRUCTURE_ID = :v_apprv_path_id;
          
        dbms_output.put_line('Using '||   :v_apprv_hierarchy ||'  approval hierarchy. Approval Hierarchy ID is '||:v_apprv_path_id);
        
        -- loop until no more employees in hierarchy. 
        :v_curr_emp_id := :v_employee_id;
        l_counter := 0;
        Loop
              
              SELECT p.full_name into :v_fullname
              FROM PER_ALL_PEOPLE_F p
              where p.person_id = :v_curr_emp_id
              and p.effective_start_date = (select max(effective_start_date) from PER_ALL_PEOPLE_F p2 where p2.person_id =p.person_id) 
              and rownum =1;
           
              -- Get emp's superior data
              open  D1(:v_curr_emp_id);
              fetch D1 into :v_sup_id, :v_sup_level, :v_sup_name;  --retrieve only first row, ignore the remaining ones. 
              if D1%NOTFOUND then 
                 :v_sup_id := null;
                 :v_sup_name := null;
              end if;
              close D1;

              dbms_output.put_line('.');
              dbms_output.put_line('****************************************************************************************************************************************************');
              dbms_output.put_line('Employee name is '||:v_fullname ||' (employee ID is '|| :v_curr_emp_id ||'). Next approver name is '|| :v_sup_name   ||' (employee ID '|| :v_sup_id  || ').' );
              dbms_output.put_line('* Checks for this employee '); 
              
              dbms_output.put_line('.');
              dbms_output.put_line('  FND User Validation (FND_USERS)');
              l_counter2 := 0;
              for i in CHK1(:v_curr_emp_id) loop
                 dbms_output.put_line('   FND User ID: '||i.user_id||', FND Username: '||i.user_name||', e-mail address: '||i.email_address||', Start Date: '||i.start_date||', End Date: '|| i.end_date);
                 l_counter2 := l_counter2 + 1;
              end loop;
              if l_counter2 > 1 then
                  dbms_output.put_line('Warning: This employee has multiple user names.');
                  dbms_output.put_line('Action: Please ensure the employee is associated to only one application user: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is: System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Use the employee name to find the user record');
                  dbms_output.put_line('        c. Do changes to ensure that only one user is associated to the employee');
                  dbms_output.put_line('        d. Save changes');
              elsif l_counter2 = 0 then
                  dbms_output.put_line('Warning: This employee is not assigned to any active FND user.');
                  dbms_output.put_line('Action: Please make sure employee is assigned to a valid FND user and verify the start and end dates include today: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is: System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Use the employee name to find the user record');
                  dbms_output.put_line('        c. Verify that user is not end dated (null effective end date or later than current date). The user will be automatically end-dated when password expires depending on the password expiration settings defined in the Define Users form.');
                  dbms_output.put_line('        d. Save changes');
              end if;
              
              dbms_output.put_line('.');
              dbms_output.put_line('  Position Assignment Validation (PER_ALL_ASSIGNMENTS)');
              l_counter2 := 0;
              for i in CHK2(:v_curr_emp_id) loop
                 dbms_output.put_line('   Position Name: '||i.name || ', Position ID: '||i.position_id||', Assignment Type: '||i.Assigment_Type||', effective start date: '||i.effective_start_date||', effective end date: '||i.effective_end_date);  
                 :v_curr_position := i.position_id;
                 l_counter2 := l_counter2 + 1;
              end loop;
              if l_counter2 < 1 then
                  dbms_output.put_line('Error: Cannot find position for this employee');
                  dbms_output.put_line('Action: Verify the employee is not terminated and run the Fill Employee Hierarchy concurrent request to refresh the hierarchy.');
              end if;
              
              dbms_output.put_line('.');
              dbms_output.put_line('  WF User Validation (WF_USERS)');
              l_counter2 := 0;
              for i in CHK3(:v_curr_emp_id) loop
                 dbms_output.put_line('    Name: '||i.name||', Display Name: '||i.display_name||', Status: '||i.status||', E-mail Address: '||i.email_address||', Start Date: '||i.start_date||', Expiration Date: '||i.expiration_date);
                 l_counter2 := l_counter2 + 1;
              end loop;
              if l_counter2 = 0 then
                  dbms_output.put_line('Warning: Username does not exist in the workflow tables.');
                  dbms_output.put_line('Action: Follow these steps to synchronize the user: ');
                  dbms_output.put_line('        a. Go to the Define Users form. Navigation is : System Administrator Responsibility > Security > Users > Define');
                  dbms_output.put_line('        b. Query user');
                  dbms_output.put_line('        c. Remove values from person name and email address and save changes');
                  dbms_output.put_line('        d. Re-Query user');
                  dbms_output.put_line('        e. Re-add the data in the person region and save the changes.');
              end if;
              
              dbms_output.put_line('.');
              dbms_output.put_line('  Employee Dates Validation (PER_PEOPLE)');
              l_counter2 := 0;
              for i in CHK4(:v_curr_emp_id) loop
                 dbms_output.put_line('    Person ID: '||i.person_id||', Full Name: '||i.full_name||', Business Group ID: '||i.business_group_id||', Employee Number: '||i.employee_number||', Start Date: '||i.effective_start_date||', End Date: '||i.effective_end_date);
                 l_counter2 := l_counter2 + 1;
              end loop;
              if l_counter2 = 0 then
                  dbms_output.put_line('Error: Username associated to a terminated employee.');
                  dbms_output.put_line('Action: Verify the employee is not terminated and run the Fill Employee Hierarchy concurrent request to refresh the hierarchy ');
              end if;
             
              dbms_output.put_line('.');
              dbms_output.put_line('  Assignments For Position Hierarchy ');
              l_counter2 := 0;
              dbms_output.put_line('.');
              dbms_output.put_line('   DOCUMENT TYPE                        APPRV GROUP NAME      RULE             RULE TYPE             AMOUNT LIMIT          ACCOUNT RANGE LOW               ACCOUNT RANGE HIGH  ');
              dbms_output.put_line('   ===================================  ====================  ===============  ====================  ====================  ==============================  ==============================');
              dbms_output.put_line('.');
              for i in ASGN(:v_curr_position) loop
                 dbms_output.put_line('   '||rpad(i.control_function_name, 35)||'  '||rpad(i.control_group_name, 20)||'  '||rpad(i.rule_type_code,15)||'  '||rpad(i.OBJECT_CODE, 20)||'  '||rpad(nvl(i.amount_limit,'null'),20)||'  '||rpad(i.account_range_low,30)||'  '||rpad(i.account_range_high,30));
                 --dbms_output.put_line('-- '||i.control_function_name||'  '||i.control_group_name||'  '||i.rule_type_code||'  '||i.OBJECT_CODE||'  '||i.amount_limit||'  '||i.account_range_low||'  '||i.account_range_high);
                 --dbms_output.put_line('-- '||substr(1,23, i.control_function_name)||'  '||substr(1,20, i.control_group_name)||'  '||substr(1,15, i.rule_type_code)||'  '||substr(1,20, i.OBJECT_CODE)||'  '||substr(1,20, 'i.amount_limit')||'  '||substr(1, 40, i.account_range_low)||'  '||substr(1,40,i.account_range_high));
                 l_counter2 := l_counter2 + 1;
              end loop;
              if l_counter2 = 0 then
                  dbms_output.put_line('Warning: No Approval Assignments found for this document type and position.');
                  dbms_output.put_line('Action: Assign an approval group to this document type and position if needed. Navigation is: PO Responsibility > Setup > Approvals > Approval Assignments.');
              end if;
              dbms_output.put_line('.');
              dbms_output.put_line('.');
                         
              dbms_output.put_line ('  Verify Approval Authority'); 
              PO_DOCUMENT_ACTION_PVT.VERIFY_AUTHORITY( 
                                      P_DOCUMENT_ID      => :v_doc_hdr_id , 
                                      P_DOCUMENT_TYPE    => :v_doc_type, 
                                      P_DOCUMENT_SUBTYPE => :v_doc_subtype, 
                                      P_EMPLOYEE_ID      => :v_curr_emp_id, 
                                      X_RETURN_STATUS    => :v_ret_status, 
                                      X_RETURN_CODE      => :v_ret_code, 
                                      X_EXCEPTION_MSG    => :v_exception_msg, 
                                      X_AUTH_FAILED_MSG  => :v_auth_fail_msg);

              if (:v_ret_status = 'S') then
                 if (:v_ret_code is null) then
                    dbms_output.put_line('   Test Successful. Employee id: '||:v_curr_emp_id||' has authority to approve this document');
                 else 
                    dbms_output.put_line('   Test Failed. Employee id: '||:v_curr_emp_id||' has no authority to approve this document');
                    dbms_output.put_line('   Authorization Failure Messages is: '|| substr(:v_auth_fail_msg, 1,180));
                 end if;
              else
                 dbms_output.put_line('Error: Test execution of PO_DOCUMENT_ACTION_PVT.VERIFY_AUTHORITY failed');
                 dbms_output.put_line('       Exception Message: '||substr(:v_exception_msg, 1, 180));
                 dbms_output.put_line('       Authorization Failed Message: '||substr(:v_auth_fail_msg,1,180));
              end if;
              dbms_output.put_line('* Checks for this employee completed!');
              
              :v_curr_emp_id := :v_sup_id;
              l_counter := l_counter+1;
              Exit when (:v_sup_id is null) or (l_counter > 100);
        end loop;
        
   end if;
    
    Exception
      When My_Error then 
         null;    --do nothing. 
end;
/

SPOOL OFF;
prompt output file name is POAPPRVCHAIN&&DOCUMENT_NUMBER-&&RELEASE_NUMBER
exit;