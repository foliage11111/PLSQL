 
- -------------------------------------------------------------------------------------------�빺��ͷ��Ϣ       po_requisition_headers_all
  --  prh.authorization_status --δ����ʱΪINCOMPLETE,�������Ϊ
      select * 
from po_requisition_headers_all prh  
   where prh .segment1='20'  
    and prh.org_id='4555'
 order by  prh .requisition_header_id desc                           
 
 
 ---------------------------------------------------------------------------------------�빺������Ϣ   po_requisition_lines_all
select prl.requisition_line_id,
prl.*
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1 = '20'           --�빺�����
 and prh.org_id=4555
and prh.type_lookup_code  ='PURCHASE');


- -----------------------------------------------------------------------------------------------�빺��������    po_req_distributions_all
select *
from po_req_distributions_all prda
where prda.requisition_line_id in
(select prl.requisition_line_id
from po_requisition_lines_all prl
where prl.requisition_header_id in
(select prh.requisition_header_id
from po_requisition_headers_all prh
where prh.segment1  ='20'        --�빺����ͷ
      and prh.org_id=4555
and prh.type_lookup_code = 'PURCHASE'));
 -------------------------------------------------------�ɹ�ѯ�۵�     PO_headers_ALL        ��·����PO/�ɹ�����/ѯ�۵���----------------------------------------

--     ��ͷ
  select * from PO.PO_headers_ALL  pha where pha.org_id=4555
	 and pha.type_lookup_code='RFQ'   order by pha.last_update_date desc

---�ɹ�ѯ�۵�        
----- ����
select * from PO.PO_LINES_ALL t where t.org_id=4555 and t.po_header_id=130331 order by t.last_update_date desc
  ---------------------------------------------------------------�ɹ����۵�           PO_headers_ALL----------------------------
----�ɹ����۵���ͷ
    
  select * from PO.PO_headers_ALL  pha where pha.org_id=4555 
	and pha.type_lookup_code='QUOTATION'   order by pha.last_update_date desc

 
----- �ɹ����۵� ����

select * from PO.PO_LINES_ALL t where t.org_id=4555 order by t.last_update_date desc
 ----------------------------------------------------------------------------------------------------------o_headers_all �ɹ�����ͷ��------------------------------------------

--pha.type_lookup_code, --��׼�ɹ���ΪSTANDARD,һ����Э��ΪBLANKET
 
--����,δ����ʱΪ  INCOMPLETE��������Ϊ  APPROVED
select pha.*
  from po_headers_all pha where pha.segment1  ='112'  --�ɹ�������
and pha.org_id=4555

--po_lines_all �ɹ������б�
 
select  pla.* 
from po_lines_all pla
where po_header_id       in
(select po_header_id from po_headers_all where segment1=  '113' and org_id=4555);
 
  --------------------------------------------------po_line_locations_all �ɹ������еķ��ͱ� 
--po_line_idpo_lines_all.po_line_id
--��������˰�ťʱ,ϵͳ���Զ�������һ�з�����,�ɸ�����Ҫ�ֹ������µķ�����
--(����ͬһ�ɹ������е����Ͽ��ܻᷢ����ͬ�ĵص�,�˱��¼���Ϸ������)
--����Ϊȡ�������䷢�˵Ĺ�ϵ(���ܴ��ڶ�η���)
 
select *
from po_line_locations_all plla
where plla.po_header_id 
in (select po_header_id from po_headers_all where segment1 = '84' and org_id=4555);
 

 -------------------------------------po_distributions_all �ɹ����������еķ���� 
--line_location_idpo_line_location_all.line_location_id
--����ͬһ�ص������Ҳ���ܷ��ڲ�ͬ���ӿ��,�˱��¼���Ϸ������
 
 
select *
from po_distributions_all
where po_header_id     in
(select po_header_id from po_headers_all where segment1=  '84' and org_id=4555);
 

--����po_distribution_all �����,�����SOURCE_DISTRIBUTION_ID ��ֵ, ���Ӧ�ڼƻ��ɹ�������
/*���ϸ�����ϵ�����һ�Զ��ϵ�� */
--------------------------------------------------------------------------------------------------------po_releases_all ��������
--�ñ����һ����Э���Լ��ƻ��ɹ�����release,����ÿһ�ŷ��ŵ�һ����Э����߼ƻ��ɹ��������������֮��Ӧ
--������ɹ�Ա�����ڣ��ͷ�״̬���ͷź��룬ÿһ���ͷ��ж�������һ���Ĳɹ����ķ�����Ϣ��֮��Ӧ(PO_LINE_LOCATIONS_ALL).
--ÿ��һ��Realese,PO_distributions_all�ͻ�����һ����¼�����Ǽƻ����������ԡ�

select * from po_releases_all pra
 where pra.org_id=4555 
order by     pra.last_update_date desc


select * from PO_LINE_LOCATIONS_ALL t    where t.po_header_id=133309
  
   ---------------------------------------------------------------����(·��:(INV)/������/����/����)----------------------------------------
--1.rcv_shipment_headers ���շ���ͷ��
--��¼�ɹ������Ľ��������ͷ��
select *
from rcv_shipment_headers rsh
where rsh.shipment_header_id in
(select shipment_header_id
from rcv_shipment_lines
where po_header_id = 134316);


--2.rcv_shipment_lines ���շ����б�
--��¼�ɹ������ķ��͵��еĽ������
select * from rcv_shipment_lines where po_header_id = 134316;

  ----------------------------------------------------------------------------------------------------------------------------------------------------
--3.rcv_transactions �����������
--��¼�ɹ������ķ����е�RECEIVE����Ϣ
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
 
--����(·��:(INV)/������/����/����������)
--����������:����֮��,��ʵ���ڻ���û����⡣
--rcv_transactions �����������
--��¼�ɹ������ķ����е�ACCEPT����Ϣ
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code = 'RCV' --�����յ�����
and rt.source_document_code = 'PO' --�����յ�����
and rt.transaction_type = 'RECEIVE' --�����յ�����
and rt.destination_type_code = 'RECEIVE' --�����յ�����
and rt.organization_id=4555  
and (rt.po_header_id  in (select pha.po_header_id
from po_headers_all pha
where segment1 = '112') 
         )
 


-- ���
--��Ϊ�漰������,����,�ڿ����������л�������Ӧ�ļ�¼��
--����Mtl_material_transactions����,�������Ӧ����������¼��
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_type_id = 18 --po����
and mmt.transaction_action_id = 27 --���������
and mmt.transaction_source_type_id = 1 --�ɹ�����
and mmt.organization_id=4555    ---vision china         org_id ��organization_id�᲻���в�ͬ��

--and (mmt.transaction_source_id  ='130338')    --po_header_id
 

--��ʱ,rcv_transactions��״̬��Ϊ
select rt.transaction_id,
rt.transaction_type,
rt.destination_type_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code = 'RCV' --����������
and rt.source_document_code=  'PO' --����������
and rt.transaction_type  ='DELIVER' --����������
and rt.destination_type_code  ='INVENTORY' --����������
and rt.organization_id=4555    ---vision china  
and (rt.po_header_id in  (select pha.po_header_id  from po_headers_all pha where segment1 ='112') 
       )



  ----------------------------------------------------------------------------------------------------------------------------------------------------

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
and rt.transaction_type = 'RETURN TO RECEIVING' --�˻�������
and rt.source_document_code  ='PO'
and rt.destination_type_code=  'RECEIVING'
and rt.organization_id=4555  
   order by   rt.creation_date desc
	
select mmt.*
from mtl_material_transactions mmt
where mmt.transaction_source_id  =4105
and mmt.transaction_type_id = 36                --��Ӧ���˻�
and mmt.transaction_action_id=  1                        --�ӿ�淢��
and mmt.transaction_source_type_id = 1              --�ɹ�����
 and mmt.organization_id=4555              
 --and (mmt.transaction_source_id  ='130338')    --po_header_id
    order by   mmt.creation_date desc  
		
		
--2.����˻�����Ӧ�̣������������ݡ�˳��Ϊ: ���----> ����----> ��Ӧ�̣�
--a.����˻�������
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type = 'RETURN TO RECEIVING' --���˻�������
and rt.source_document_code = 'PO'
and rt.destination_type_code=  'INVENTORY'
 
and rt.organization_id=4555  
   order by   rt.creation_date desc
	 
--b.�����˻�����Ӧ��
select rt.destination_type_code,
rt.interface_source_code,
rt.*
from rcv_transactions rt
where rt.interface_source_code is null
and rt.transaction_type  ='RETURN TO VENDOR' --�˻�����Ӧ��
and rt.source_document_code = 'PO'
and rt.destination_type_code=  'RECEIVING'
and rt.organization_id=4555  
--and po_header_id = 4105;
   order by   rt.creation_date desc


select mmt.*
from mtl_material_transactions mmt
where  mmt.transaction_type_id=  36 --��Ӧ���˻�
and mmt.transaction_action_id = 1 --�ӿ�淢��
 and mmt.transaction_source_type_id = 1; --�ɹ�����
---and (mmt.transaction_source_id  ='130338')    --po_header_id
and mmt.organization_id=4555  
   order by   mmt.creation_date desc
