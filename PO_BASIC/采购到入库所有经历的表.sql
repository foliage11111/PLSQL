--�ɹ�������������ı�
--0.�빺��
--�����빺����ʽ��
--a.�����ϵͳ�����빺�Ľӿڱ�PO_REQUISITIONS_INTERFACE_ALL,����������(����:��������)
select *
from po_requisitions_interface_all
where interface_source_code  'TEST KHJ';
--b.��ϵͳ�д����빺��(·��:(PO)/����/����)
--�빺��ͷ��Ϣ
select prh.requisition_header_id,
prh.authorization_status --δ����ʱΪINCOMPLETE,�������Ϊ
from po_requisition_headers_all prh
where prh.segment1  '600000'
and prh.type_lookup_code  'PURCHASE';
--�빺������Ϣ
select prl.requisition_line_id,
prl.*
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1  '600000'
and prh.type_lookup_code  'PURCHASE');
--�빺��������
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
--1.�ɹ������Ĵ�����·����PO/�ɹ�����/�ɹ�������
--po_headers_all �ɹ�����ͷ��
select pha.po_header_id,
pha.segment1,
pha.agent_id,
pha.type_lookup_code, --��׼�ɹ���ΪSTANDARD,һ����Э��ΪBLANKET
decode(pha.approved_flag,
'R',
pha.approved_flag,
nvl(pha.authorization_status, 'INCOMPLETE')), --����,δ����ʱΪINCOMPLETE��������ΪAPPROVED
po_headers_sv3.get_po_status(pha.po_header_id) --������ɹ�����δ����ʱ��po״̬Ϊδ��ɣ�������״̬Ϊ��׼
from po_headers_all pha
where segment1  300446; --�ɹ�������
--po_lines_all �ɹ������б�
select pla.po_line_id,
pla.line_type_id
from po_lines_all pla
where po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
/*
ȡ���������۶���ͷ���е�����:
�漰�� Po_headers_all,Po_lines_all
�߼����£�
����ͷ����������ԣ���ͨ��Po_header_id��ͷ���б��������
APPROVED_FLAGY
*/
--po_line_locations_all �ɹ������еķ��ͱ�(·��:(PO)/�ɹ�����/�ɹ�����/����(T))
--po_line_idpo_lines_all.po_line_id
--��������˰�ťʱ,ϵͳ���Զ�������һ�з�����,�ɸ�����Ҫ�ֹ������µķ�����
--(����ͬһ�ɹ������е����Ͽ��ܻᷢ����ͬ�ĵص�,�˱��¼���Ϸ������)
--����Ϊȡ�������䷢�˵Ĺ�ϵ(���ܴ��ڶ�η���)
select *
from po_line_locations_all plla
where plla.po_line_id 
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446));
--����
select *
from po_line_locations_all plla
where plla.po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
--4��po_distributions_all �ɹ����������еķ����(·����PO/�ɹ�����/�ɹ�����/����(T)/����(T))
--line_location_idpo_line_location_all.line_location_id
--����ͬһ�ص������Ҳ���ܷ��ڲ�ͬ���ӿ��,�˱��¼���Ϸ������
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
--����
select *
from po_distributions_all
where po_header_id 
(select po_header_id from po_headers_all where segment1  300446);
--����
select *
from po_distributions_all pda
where pda.po_line_id 
(select pla.po_line_id
from po_lines_all pla
where po_header_id  (select po_header_id
from po_headers_all
where segment1  300446));
--����po_distribution_all �����,�����SOURCE_DISTRIBUTION_ID ��ֵ, ���Ӧ�ڼƻ��ɹ�������
/*���ϸ�����ϵ�����һ�Զ��ϵ�� */
--po_releases_all ��������
--�ñ����һ����Э���Լ��ƻ��ɹ�����release,����ÿһ�ŷ��ŵ�һ����Э����߼ƻ��ɹ��������������֮��Ӧ
--������ɹ�Ա�����ڣ��ͷ�״̬���ͷź��룬ÿһ���ͷ��ж�������һ���Ĳɹ����ķ�����Ϣ��֮��Ӧ(PO_LINE_LOCATIONS_ALL).
--ÿ��һ��Realese,PO_distributions_all�ͻ�����һ����¼�����Ǽƻ����������ԡ�
--
select * from po_releases_all where po_header_id  &po_header_id;
--����(·��:(INV)/������/����/����)
--1.rcv_shipment_headers ���շ���ͷ��
--��¼�ɹ������Ľ��������ͷ��
select *
from rcv_shipment_headers rsh
where rsh.shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id  4105);
--2.rcv_shipment_lines ���շ����б�
--��¼�ɹ������ķ��͵��еĽ������
select * from rcv_shipment_lines where po_header_id  4105;
--3.rcv_transactions �����������
--��¼�ɹ������ķ����е�RECEIVE����Ϣ
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
--4.rcv_receiving_sub_ledger �ݼ�Ӧ����
--��¼�ɹ��������պ�,�������ݼ�Ӧ����Ϣ(��������������ķ�����)
--������¼�ĳ���: RCV_SeedEvents_PVT>RCV_CreateAccounting_PVT
/* po_line_locations.accrue_on_receipt_flag �����Ƿ������¼*/
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
--����(·��:(INV)/������/����/����������)
--����������:����֮��,��ʵ���ڻ���û����⡣
--rcv_transactions �����������
--��¼�ɹ������ķ����е�ACCEPT����Ϣ
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code  'RCV' --�����յ�����
and rt.source_document_code  'PO' --�����յ�����
and rt.transaction_type  'RECEIVE' --�����յ�����
and rt.destination_type_code  'RECEIVE' --�����յ�����
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
-- ���
--��Ϊ�漰������,����,�ڿ����������л�������Ӧ�ļ�¼��
--����Mtl_material_transactions����,�������Ӧ����������¼��
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_type_id  18 --po����
and mmt.transaction_action_id  27 --���������
and mmt.transaction_source_type_id  1 --�ɹ�����
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
--��ʱ,rcv_transactions��״̬��Ϊ
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code  'RCV' --����������
and rt.source_document_code  'PO' --����������
and rt.transaction_type  'DELIVER' --����������
and rt.destination_type_code  'INVENTORY' --����������
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
--�˻�
--˵��:
--�˻�������ʱ������һ����¼���˻�����Ӧ��ʱ�������������ݡ� �ɼ��˻���ʵ��˳��Ϊ: ���----> ����----> ��Ӧ��
--�������˻������ջ����˻�����Ӧ��,����������,�������������¼��
--����,������������յ����������෴�����Ҳ����ļ�¼����RETURN to RECEIVING��
--1.����˻�������
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  'RETURN TO RECEIVING' --�˻�������
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
--2.����˻�����Ӧ�̣������������ݡ�˳��Ϊ: ���----> ����----> ��Ӧ�̣�
--a.����˻�������
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  'RETURN TO RECEIVING' --���˻�������
and rt.source_document_code  'PO'
and rt.destination_type_code  'INVENTORY'
and po_header_id  4105;
--b.�����˻�����Ӧ��
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  'RETURN TO VENDOR' --�˻�����Ӧ��
and rt.source_document_code  'PO'
and rt.destination_type_code  'RECEIVING'
and po_header_id  4105;
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_source_id  4105
and mmt.transaction_type_id  36 --��Ӧ���˻�
and mmt.transaction_action_id  1 --�ӿ�淢��
and mmt.transaction_source_type_id  1; --�ɹ�����
