--采购到入库所经历的表
--0.请购单
--创建请购单方式有
--a.从外挂系统导入请购的接口表PO_REQUISITIONS_INTERFACE_ALL,并允许请求(名称:导入申请)
select *
from po_requisitions_interface_all
where interface_source_code  'TEST KHJ';
--b.在系统中创建请购单(路径:(PO)/申请/申请)
--请购单头信息
select prh.requisition_header_id,
prh.authorization_status --未审批时为INCOMPLETE,审批完后为
from po_requisition_headers_all prh
where prh.segment1  '600000'
and prh.type_lookup_code  'PURCHASE';
--请购单行信息
select prl.requisition_line_id,
prl.*
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1  '600000'
and prh.type_lookup_code  'PURCHASE');
--请购单分配行
select *
from po_req_distributions_all prda
where prda.requisition_line_id in
(select prl.requisition_line_id
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1  '600000'
and prh.type_lookup_code  'PURCHASE'));
--1.采购订单的创建（路径：PO/采购订单/采购订单）
--po_headers_all 采购订单头表
select pha.po_header_id,
pha.segment1,
pha.agent_id,
pha.type_lookup_code, --标准采购单为STANDARD,一揽子协议为BLANKET
decode(pha.approved_flag,
'R',
pha.approved_flag,
nvl(pha.authorization_status, 'INCOMPLETE')), --审批,未审批时为INCOMPLETE，审批后为APPROVED
po_headers_sv3.get_po_status(pha.po_header_id) --刚下完采购单，未审批时，po状态为未完成，审批后，状态为批准
from po_headers_all pha
where segment1  300446; --采购单号码
--po_lines_all 采购订单行表
select pla.po_line_id,
pla.line_type_id
from po_lines_all pla
where po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
/*
取已审批销售订单头和行的数据:
涉及表： Po_headers_all,Po_lines_all
逻辑如下：
限制头表的如下属性，并通过Po_header_id把头、行表关联起来
APPROVED_FLAGY
*/
--po_line_locations_all 采购订单行的发送表(路径:(PO)/采购订单/采购订单/发运(T))
--po_line_idpo_lines_all.po_line_id
--当点击发运按钮时,系统会自动创建第一行发运行,可根据需要手工创建新的发运行
--(例如同一采购订单行的物料可能会发往不同的地点,此表记录物料发送情况)
--下面为取订单与其发运的关系(可能存在多次发运)
select *
from po_line_locations_all plla
where plla.po_line_id 
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446));
--或者
select *
from po_line_locations_all plla
where plla.po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
--4、po_distributions_all 采购订单发送行的分配表(路径：PO/采购订单/采购订单/发运(T)/分配(T))
--line_location_idpo_line_location_all.line_location_id
--发往同一地点的物料也可能放在不同的子库存,此表记录物料分配情况
select *
from po_distributions_all pda
where pda.line_location_id in
(select plla.line_location_id
from po_line_locations_all plla
where plla.po_line_id 
(select pla.po_line_id
from po_lines_all pla
where po_header_id 
(select po_header_id
from po_headers_all
where segment1  300446)));
--或者
select *
from po_distributions_all
where po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
--或者
select *
from po_distributions_all pda
where pda.po_line_id 
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446));
--对于po_distribution_all 表而言,如果其SOURCE_DISTRIBUTION_ID 有值, 其对应于计划采购单发放
/*以上各表从上到下是一对多关系的 */
--po_releases_all 订单发放
--该表包含一揽子协议以及计划采购单的release,对于每一张发放的一揽子协议或者计划采购单都有相关行与之对应
--其包含采购员，日期，释放状态，释放号码，每一个释放行都有至少一条的采购单的发运信息与之对应(PO_LINE_LOCATIONS_ALL).
--每做一次Realese,PO_distributions_all就会新增一条记录。这是计划订单的特性。
--
select * from po_releases_all where po_header_id  &po_header_id;
--接收(路径:(INV)/事务处理/接收/接收)
--1.rcv_shipment_headers 接收发送头表
--记录采购订单的接收情况的头表
select *
from rcv_shipment_headers rsh
where rsh.shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id  4105);
--2.rcv_shipment_lines 接收发送行表
--记录采购订单的发送的行的接收情况
select * from rcv_shipment_lines where po_header_id  4105;
--3.rcv_transactions 接收事务处理表
--记录采购订单的发送行的RECEIVE的信息
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code  'RCV'
and rt.source_document_code  'PO'
and (rt.po_header_id  (select pha.po_header_id
from po_headers_all pha
where segment1  300446) or
rt.po_line_id in
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446)) or
rt.shipment_header_id 
(select rsh.shipment_header_id
from rcv_shipment_headers rsh
where shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id  4105)) or
rt.shipment_line_id in
(select shipment_line_id
from rcv_shipment_lines
where po_header_id  4105));
--4.rcv_receiving_sub_ledger 暂记应付表
--记录采购订单接收后,产生的暂记应付信息(接收事务处理产生的分配行)
--产生分录的程序: RCV_SeedEvents_PVT>RCV_CreateAccounting_PVT
/* po_line_locations.accrue_on_receipt_flag 控制是否产生分录*/
select nvl(poll.accrue_on_receipt_flag, 'N')
into l_accrue_on_receipt_flag
from po_line_locations poll
where poll.line_location_id  p_rcv_events_tbl(l_ctr_first).po_line_location_id;
IF ((l_accrue_on_receipt_flag  'Y' OR
p_rcv_events_tbl(i).procurement_org_flag  'N') AND
p_rcv_events_tbl(i).event_type_id NOT IN
(RCV_SeedEvents_PVT.INTERCOMPANY_INVOICE,RCV_SeedEvents_PVT.INTERCOMPANY_REVERSAL)) THEN
l_stmt_num : 50
IF G_DEBUG  'Y' AND FND_LOG.LEVEL_EVENT > FND_LOG.G_CURRENT_RUNTIME_LEVEL THEN
FND_LOG.string(FND_LOG.LEVEL_EVENT,G_LOG_HEAD'.'l_api_name'.'l_stmt_num
,'Creating accounting entries in RRS')
END IF
IF G_DEBUG  'Y' AND FND_LOG.LEVEL_STATEMENT > FND_LOG.G_CURRENT_RUNTIME_LEVEL THEN
FND_LOG.string(FND_LOG.LEVEL_STATEMENT,G_LOG_HEAD'.'l_api_name'.'l_stmt_num
,'Creating accounting entries for accounting_event_id : 'l_accounting_event_id)
END IF
-- Call Account generation API to create accounting entries
RCV_CreateAccounting_PVT.Create_AccountingEntry(
p_api_version > 1.0,
x_return_status > l_return_status,
x_msg_count > l_msg_count,
x_msg_data > l_msg_data,
p_accounting_event_id > l_accounting_event_id,
/* Support for Landed Cost Management */
p_lcm_flag > p_lcm_flag)
IF l_return_status <> FND_API.g_ret_sts_success THEN
l_api_message : 'Error in Create_AccountingEntry API'
IF G_DEBUG  'Y' AND FND_LOG.LEVEL_UNEXPECTED > FND_LOG.G_CURRENT_RUNTIME_LEVEL THEN
FND_LOG.string(FND_LOG.LEVEL_UNEXPECTED,G_LOG_HEAD '.'l_api_namel_stmt_num
,'Insert_RAEEvents : 'l_stmt_num' : 'l_api_message)
END IF
RAISE FND_API.g_exc_unexpected_error
END IF
select *
from rcv_receiving_sub_ledger
where rcv_transaction_id in
(select transaction_id
from rcv_transactions
where po_header_id  4105);
--接受(路径:(INV)/事务处理/接收/接收事务处理)
--接收事务处理:接收之后,其实现在还并没有入库。
--rcv_transactions 接收事务处理表
--记录采购订单的发送行的ACCEPT的信息
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code  'RCV' --做接收的条件
and rt.source_document_code  'PO' --做接收的条件
and rt.transaction_type  'RECEIVE' --做接收的条件
and rt.destination_type_code  'RECEIVE' --做接收的条件
and (rt.po_header_id  (select pha.po_header_id
from po_headers_all pha
where segment1  300446) or
rt.po_line_id in
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446)) or
rt.shipment_header_id 
(select rsh.shipment_header_id
from rcv_shipment_headers rsh
where shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id  4105)) or
rt.shipment_line_id in
(select shipment_line_id
from rcv_shipment_lines
where po_header_id  4105));
-- 入库
--因为涉及入库操作,所以,在库存事务处理表中会留下相应的记录。
--即在Mtl_material_transactions表中,会存在相应的两条入库记录。
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_type_id  18 --po接收
and mmt.transaction_action_id  27 --接收至库存
and mmt.transaction_source_type_id  1 --采购订单
and (mmt.transaction_source_id  4105 --po_header_id
or mmt.rcv_transaction_id in
(select rt.transaction_id
from rcv_transactions rt
where rt.interface_source_code  'RCV'
and rt.source_document_code  'PO'
and (rt.po_header_id 
(select pha.po_header_id
from po_headers_all pha
where segment1  300446))));
--此时,rcv_transactions的状态变为
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code  'RCV' --做入库的条件
and rt.source_document_code  'PO' --做入库的条件
and rt.transaction_type  'DELIVER' --做入库的条件
and rt.destination_type_code  'INVENTORY' --做入库的条件
and (rt.po_header_id  (select pha.po_header_id
from po_headers_all pha
where segment1  300446) or
rt.po_line_id in
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446)) or
rt.shipment_header_id 
(select rsh.shipment_header_id
from rcv_shipment_headers rsh
where shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id  4105)) or
rt.shipment_line_id in
(select shipment_line_id
from rcv_shipment_lines
where po_header_id  4105));
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
and rt.transaction_type  'RETURN TO RECEIVING' --退货至接受
and rt.source_document_code  'PO'
and rt.destination_type_code  'RECEIVING'
and po_header_id  4105
and po_line_id  9938;
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_source_id  4105
and mmt.transaction_type_id  36
and mmt.transaction_action_id  1
and mmt.transaction_source_type_id  1;
--2.库存退货至供应商（产生两条数据。顺序为: 库存----> 接收----> 供应商）
--a.库存退货至接收
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  'RETURN TO RECEIVING' --先退货至接收
and rt.source_document_code  'PO'
and rt.destination_type_code  'INVENTORY'
and po_header_id  4105;
--b.接收退货至供应商
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  'RETURN TO VENDOR' --退货至供应商
and rt.source_document_code  'PO'
and rt.destination_type_code  'RECEIVING'
and po_header_id  4105;
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_source_id  4105
and mmt.transaction_type_id  36 --向供应商退货
and mmt.transaction_action_id  1 --从库存发放
and mmt.transaction_source_type_id  1; --采购订单
