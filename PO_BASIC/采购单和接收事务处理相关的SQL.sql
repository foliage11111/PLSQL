--�ɹ����ͽ�����������ص�SQL 

--�Ӳɹ����鿴RCV_TRANSACTION��ֻ����po_headers_all.po_header_id��po_lines_all.po_line_id
--(��ʵֻ��po_line_id�Ϳ��Ե��ˡ���)�������ӡ�

select rsh.receipt_num,
       rt.transaction_type,
       pha.segment1        as po_num,
       pla.line_num,
       msi.segment1        as item_num,
       msi.description,
       rt.*
  from rcv_transactions     rt,
       rcv_shipment_headers rsh,
       po_headers_all       pha,
       po_lines_all         pla,
       mtl_system_items_b   msi
 where rt.shipment_header_id = rsh.shipment_header_id
   and rt.po_header_id = pha.po_header_id
   and rt.po_line_id = pla.po_line_id
   and pla.org_id = msi.organization_id
   and pla.item_id = msi.inventory_item_id
   and pha.segment1 = '84'    
	 and pha.org_id=130338
 order by rt.creation_date;

--���⣬�����Ҫ���ҽ���δ�����߼���δ�������ݣ�����ֱ�Ӳ���RCV_SUPPLY��
--����ֻ����ڽ��������������ǰ�����һ�ʼ�¼������ͨ��po_lines_all.po_line_id���ӣ�
--���ҿ���ͨ��rcv_supply.shipment_line_id����rcv_supply.transaction_id��RCV_TRANSACTION�������

select *
  from rcv_supply rs
 where 1 = 1
      --and rs.rcv_transaction_id = 252514 
   and rs.shipment_line_id = 134176
