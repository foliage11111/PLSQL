---京博环境使用sql

--物料导入用:
select b.inventory_item_id item_id,
       b.segment1 item_code,
       b.description item_descripton,
       b.primary_uom_code uom_code,
       b.primary_unit_of_measure unit_of_measure,
       b.inventory_item_status_code as item_status,
       decode(b.purchasing_item_flag, 'Y', 1, 0)as  purchasing_flag,
       b.organization_id as organization_id,
       '' as key_norms,
       -1 as created_by,
       to_char(b.creation_date,'YYYY-MM-DD') as creation_date,
       -1 as LAST_UPDATED_BY,
       to_char(b.LAST_UPDATE_DATE,'YYYY-MM-DD') as LAST_UPDATE_DATE
  from apps.mtl_system_items_b b
 where b.inventory_item_status_code = 'Active'
   and b.creation_date >= to_date('20161201','YYYYMMDD')

--（1）从Unix时间戳记转换为Oracle时间

create or replace function unix_to_oracle(in_number NUMBER) return date is
begin  
  return(TO_DATE('19700101','yyyymmdd') + in_number/86400 +TO_NUMBER(SUBSTR(TZ_OFFSET(sessiontimezone),1,3))/24);
end unix_to_oracle;

--（2）由Oracle时间Date型转换为Unix时间戳记
create or replace function oracle_to_unix(in_date IN DATE) return number is  
begin  
  return( round((in_date -TO_DATE('19700101','yyyymmdd'))*86400 - TO_NUMBER(SUBSTR(TZ_OFFSET(sessiontimezone),1,3))*3600),1);
end oracle_to_unix;
------需要增加round ,四舍五入才能保证数据没有小数
select round((sysdate -TO_DATE('19700101','yyyymmdd'))*86400 - TO_NUMBER(SUBSTR(TZ_OFFSET(sessiontimezone),1,3))*3600,1) from dual;

----人员导入用:
select ppf.person_id as employee_id
,'JB'||substr(ppf.employee_number,-6) as employee_number
,ppf.employee_number as ebs_employee_number
,ppf.last_name as employee_name
,decode(ppf.sex,'M',1,'F',0) as sex
,ppf.attribute1 as mobile_phone
,ppf.attribute2 as office_phone
,ppf.email_address as email_address
,ppf.attribute3 as contact_address
,to_char(ppf.effective_start_date,'YYYY-MM-DD') as effective_start_date
,to_char(ppf.effective_end_date,'YYYY-MM-DD') as effective_end_date
,ppf.attribute3 as home_address
,ppf.attribute17 as office_address
,paf.position_id  as position_id
,( select substr(pap.name,instr(pap.name,'.',1)-length(pap.name)) from per_all_positions pap where pap.position_id = paf.position_id ) as position_name
,paf.organization_id as organization_id
,paf.location_id as location_id
,paf.supervisor_id as supervisor_id
from  PER_ALL_PEOPLE_F ppf,  PER_ALL_ASSIGNMENTS_F paf 
where ppf.person_id=paf.person_id(+)
and TRUNC(SYSDATE) between paf.effective_start_date(+) and paf.effective_end_Date(+) and trunc(sysdate) between ppf.EFFECTIVE_START_DATE and ppf.EFFECTIVE_END_DATE

 ;
	  select * from PER_ALL_PEOPLE_F;
------------------------------------物料------------------------------------------
select * from mtl_item_categories mic where mic.INVENTORY_ITEM_ID=1257275;



select t.inventory_item_id
,t.segment1,t.description

,t.primary_uom_code
,t.primary_unit_of_measure
,t.inventory_item_status_code
,DECODE(t.purchasing_item_flag,'Y',1,0) purchasing_item_flag
,t.organization_id from mtl_system_items_b t where t.inventory_item_status_code='Active' and t.segment1='T09143548';
---------------------------------------提报计划----------------------------------------------
update Cux_Item_Req_Lines_Apply cir  set cir.STATUS=2 where cir.APPLY_NUMBER='SH216128' ;

update CUX_ITEM_REQ_APPLY  cira set cira.REC_STATE=2 ,cira.APPROVE_DATE=sysdate  where cira.APPLY_NUMBER='SH216128' ;


------------------------------------采购申请------------------------------------------

select * from PO.PO_REQUISITION_HEADERS_ALL pqh where pqh.SEGMENT1='SH216111_1';

select * from PO.PO_REQUISITION_LINES_ALL prl where prl.REQUISITION_HEADER_ID=154152;


------------------------------------采购订单------------------------------------------

select * from po.po_headers_all pha where pha.segment1='19900909';

select * from PO.PO_LINES_ALL pla where pla.PO_HEADER_ID=423448;





------------------------------------采购订单------------------------------------------