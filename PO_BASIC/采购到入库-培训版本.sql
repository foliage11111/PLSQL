 
- -------------------------------------------------------------------------------------------请购单头信息       po_requisition_headers_all
  --  prh.authorization_status --未审批时为INCOMPLETE,审批完后为
      select * 
from po_requisition_headers_all prh  
   where prh .segment1='20'  
    and prh.org_id='4555'
 order by  prh .requisition_header_id desc                           
 
 
 ---------------------------------------------------------------------------------------请购单行信息   po_requisition_lines_all
select prl.requisition_line_id,
prl.*
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1 = '20'           --请购单编号
 and prh.org_id=4555
and prh.type_lookup_code  ='PURCHASE');


- -----------------------------------------------------------------------------------------------请购单分配行    po_req_distributions_all
select *
from po_req_distributions_all prda
where prda.requisition_line_id in
(select prl.requisition_line_id
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1  ='20'        --请购单单头
      and prh.org_id=4555
and prh.type_lookup_code = 'PURCHASE'));
 -------------------------------------------------------采购询价单     PO_headers_ALL        （路径：PO/采购订单/询价单）----------------------------------------

--     单头
  select * from PO.PO_headers_ALL  pha where pha.org_id=4555
	 and pha.type_lookup_code='RFQ'   order by pha.last_update_date desc

---采购询价单        
----- 单身
select * from PO.PO_LINES_ALL t where t.org_id=4555 and t.po_header_id=130331 order by t.last_update_date desc
  ---------------------------------------------------------------采购报价单           PO_headers_ALL----------------------------
----采购报价单单头
    
  select * from PO.PO_headers_ALL  pha where pha.org_id=4555 
	and pha.type_lookup_code='QUOTATION'   order by pha.last_update_date desc

 
----- 采购报价单 单身

select * from PO.PO_LINES_ALL t where t.org_id=4555 order by t.last_update_date desc
 ----------------------------------------------------------------------------------------------------------o_headers_all 采购订单头表------------------------------------------

--pha.type_lookup_code, --标准采购单为STANDARD,一揽子协议为BLANKET
 
--审批,未审批时为  INCOMPLETE，审批后为  APPROVED
select pha.*
  from po_headers_all pha where pha.segment1  ='112'  --采购单号码
and pha.org_id=4555

--po_lines_all 采购订单行表
 
select  pla.* 
from po_lines_all pla
where po_header_id       in
(select po_header_id from po_headers_all where segment1=  '113' and org_id=4555);
 
  --------------------------------------------------po_line_locations_all 采购订单行的发送表 
--po_line_idpo_lines_all.po_line_id
--当点击发运按钮时,系统会自动创建第一行发运行,可根据需要手工创建新的发运行
--(例如同一采购订单行的物料可能会发往不同的地点,此表记录物料发送情况)
--下面为取订单与其发运的关系(可能存在多次发运)
 
select *
from po_line_locations_all plla
where plla.po_header_id 
in (select po_header_id from po_headers_all where segment1 = '84' and org_id=4555);
 

 -------------------------------------po_distributions_all 采购订单发送行的分配表 
--line_location_idpo_line_location_all.line_location_id
--发往同一地点的物料也可能放在不同的子库存,此表记录物料分配情况
 
 
select *
from po_distributions_all
where po_header_id     in
(select po_header_id from po_headers_all where segment1=  '84' and org_id=4555);
 

--对于po_distribution_all 表而言,如果其SOURCE_DISTRIBUTION_ID 有值, 其对应于计划采购单发放
/*以上各表从上到下是一对多关系的 */
--------------------------------------------------------------------------------------------------------po_releases_all 订单发放
--该表包含一揽子协议以及计划采购单的release,对于每一张发放的一揽子协议或者计划采购单都有相关行与之对应
--其包含采购员，日期，释放状态，释放号码，每一个释放行都有至少一条的采购单的发运信息与之对应(PO_LINE_LOCATIONS_ALL).
--每做一次Realese,PO_distributions_all就会新增一条记录。这是计划订单的特性。

select * from po_releases_all pra
 where pra.org_id=4555 
order by     pra.last_update_date desc


select * from PO_LINE_LOCATIONS_ALL t    where t.po_header_id=133309
  
   ---------------------------------------------------------------接收(路径:(INV)/事务处理/接收/接收)----------------------------------------
--1.rcv_shipment_headers 接收发送头表
--记录采购订单的接收情况的头表
select *
from rcv_shipment_headers rsh
where rsh.shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id = 134316);


--2.rcv_shipment_lines 接收发送行表
--记录采购订单的发送的行的接收情况
select * from rcv_shipment_lines where po_header_id = 134316;

  ----------------------------------------------------------------------------------------------------------------------------------------------------
--3.rcv_transactions 接收事务处理表
--记录采购订单的发送行的RECEIVE的信息
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt where rt.interface_source_code = 'RCV'
and rt.source_document_code = 'PO' and
 (rt.po_header_id  in 
(select pha.po_header_id
from po_headers_all pha
where segment1 = '84' and org_id=4555))


  ----------------------------------------------------------------------------------------------------------------------------------------------------
 
--接受(路径:(INV)/事务处理/接收/接收事务处理)
--接收事务处理:接收之后,其实现在还并没有入库。
--rcv_transactions 接收事务处理表
--记录采购订单的发送行的ACCEPT的信息
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code = 'RCV' --做接收的条件
and rt.source_document_code = 'PO' --做接收的条件
and rt.transaction_type = 'RECEIVE' --做接收的条件
and rt.destination_type_code = 'RECEIVE' --做接收的条件
and rt.organization_id=4555  
and (rt.po_header_id  in (select pha.po_header_id
from po_headers_all pha
where segment1 = '112') 
         )
 


-- 入库
--因为涉及入库操作,所以,在库存事务处理表中会留下相应的记录。
--即在Mtl_material_transactions表中,会存在相应的两条入库记录。
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_type_id = 18 --po接收
and mmt.transaction_action_id = 27 --接收至库存
and mmt.transaction_source_type_id = 1 --采购订单
and mmt.organization_id=4555    ---vision china         org_id 和organization_id会不会有不同？

--and (mmt.transaction_source_id  ='130338')    --po_header_id
 

--此时,rcv_transactions的状态变为
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code = 'RCV' --做入库的条件
and rt.source_document_code=  'PO' --做入库的条件
and rt.transaction_type  ='DELIVER' --做入库的条件
and rt.destination_type_code  ='INVENTORY' --做入库的条件
and rt.organization_id=4555    ---vision china  
and (rt.po_header_id in  (select pha.po_header_id  from po_headers_all pha where segment1 ='112') 
       )



  ----------------------------------------------------------------------------------------------------------------------------------------------------

--退货
--说明:
--退货至接收时，产生一条记录，退货至供应商时，产生两条数据。 可见退货的实际顺序为: 库存----> 接收----> 供应商
--不管是退货至接收还是退货至供应商,在事务处理中,都会产生两条记录。
--而且,数量符号与接收的数据正好相反。而且产生的记录都是RETURN to RECEIVING。
--1.库存退货至接受
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type = 'RETURN TO RECEIVING' --退货至接受
and rt.source_document_code  ='PO'
and rt.destination_type_code=  'RECEIVING'
and rt.organization_id=4555  
   order by   rt.creation_date desc
	
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_source_id  =4105
and mmt.transaction_type_id = 36                --向供应商退货
and mmt.transaction_action_id=  1                        --从库存发放
and mmt.transaction_source_type_id = 1              --采购订单
 and mmt.organization_id=4555              
 --and (mmt.transaction_source_id  ='130338')    --po_header_id
    order by   mmt.creation_date desc  
		
		
--2.库存退货至供应商（产生两条数据。顺序为: 库存----> 接收----> 供应商）
--a.库存退货至接收
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type = 'RETURN TO RECEIVING' --先退货至接收
and rt.source_document_code = 'PO'
and rt.destination_type_code=  'INVENTORY'
 
and rt.organization_id=4555  
   order by   rt.creation_date desc
	 
--b.接收退货至供应商
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  ='RETURN TO VENDOR' --退货至供应商
and rt.source_document_code = 'PO'
and rt.destination_type_code=  'RECEIVING'
and rt.organization_id=4555  
--and po_header_id = 4105;
   order by   rt.creation_date desc


select mmt.*
from mtl_material_transactions mmt
where  mmt.transaction_type_id=  36 --向供应商退货
and mmt.transaction_action_id = 1 --从库存发放
 and mmt.transaction_source_type_id = 1; --采购订单
---and (mmt.transaction_source_id  ='130338')    --po_header_id
and mmt.organization_id=4555  
   order by   mmt.creation_date desc
