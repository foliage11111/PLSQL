--采购单和接收事务处理相关的SQL 

--从采购单查看RCV_TRANSACTION表，只需用po_headers_all.po_header_id和po_lines_all.po_line_id
--(其实只用po_line_id就可以的了……)进行连接。

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

--另外，如果需要查找接收未入库或者检验未入库的数据，可以直接查找RCV_SUPPLY表，
--里面只会存在接收事务处理中入库前的最后一笔记录。可以通过po_lines_all.po_line_id连接，
--而且可以通过rcv_supply.shipment_line_id或者rcv_supply.transaction_id和RCV_TRANSACTION表关联。

select *
  from rcv_supply rs
 where 1 = 1
      --and rs.rcv_transaction_id = 252514 
   and rs.shipment_line_id = 134176
