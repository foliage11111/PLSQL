select *from pon_auction_headers_all t order by t.creation_date desc              ;


 select * from pon_bidding_parties    pbp order by pbp.creation_date desc;     --被邀请的供应商的列表
    
 select * from pon_auction_sections pas order by pas.creation_date desc;    --分区
 
select * from pon_bid_attribute_values pba order by pba.creation_date desc,pba.sequence_number;      --投标的需求部分 ,内容，投标值，得分值，都有。
 	                                                                                           --需求和实际是不是一个表？
	 select * from pon_attribute_scores;   --自动得分的范围？
	 
	 select * from pon_attribute_lists;     --默认的需求列表模板
	    
	 

select * from pon_bid_headers tpb order by tpb.creation_date desc;           --投标的标头	 

 
	 
select * from pon_bid_item_prices pbp   order by pbp.creation_date    desc，pbp.auction_line_number   ;
 	 
  select * from pon_auction_item_prices_all    ---以上两个有什么不同？



   select * from pon_action_history pah order by pah.action_date desc;       --执行动作，但是似乎只有暂停，审批，提交，取消 

 select * from pon_supplier_access psa  order by psa.lock_date desc;    
 
 select *from pon_supplier_activities  psb order by    psb.creation_date desc;               
 

 
 --我的想法是：应该分以下结构，询价题头一个表，题头的需求一个表，标的行一个表，供应商一个表，评分小组一个人，控制是否有一个表？合同条款是关联还是？
 
 --投标的时候，投标头一个，投标需求部分一个表，投标价格部分一个表 
 
             
 
