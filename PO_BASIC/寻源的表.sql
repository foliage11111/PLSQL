select *from pon_auction_headers_all t order by t.creation_date desc              ;


 select * from pon_bidding_parties    pbp order by pbp.creation_date desc;     --������Ĺ�Ӧ�̵��б�
    
 select * from pon_auction_sections pas order by pas.creation_date desc;    --����
 
select * from pon_bid_attribute_values pba order by pba.creation_date desc,pba.sequence_number;      --Ͷ������󲿷� ,���ݣ�Ͷ��ֵ���÷�ֵ�����С�
 	                                                                                           --�����ʵ���ǲ���һ����
	 select * from pon_attribute_scores;   --�Զ��÷ֵķ�Χ��
	 
	 select * from pon_attribute_lists;     --Ĭ�ϵ������б�ģ��
	    
	 

select * from pon_bid_headers tpb order by tpb.creation_date desc;           --Ͷ��ı�ͷ	 

 
	 
select * from pon_bid_item_prices pbp   order by pbp.creation_date    desc��pbp.auction_line_number   ;
 	 
  select * from pon_auction_item_prices_all    ---����������ʲô��ͬ��



   select * from pon_action_history pah order by pah.action_date desc;       --ִ�ж����������ƺ�ֻ����ͣ���������ύ��ȡ�� 

 select * from pon_supplier_access psa  order by psa.lock_date desc;    
 
 select *from pon_supplier_activities  psb order by    psb.creation_date desc;               
 

 
 --�ҵ��뷨�ǣ�Ӧ�÷����½ṹ��ѯ����ͷһ������ͷ������һ���������һ������Ӧ��һ��������С��һ���ˣ������Ƿ���һ������ͬ�����ǹ������ǣ�
 
 --Ͷ���ʱ��Ͷ��ͷһ����Ͷ�����󲿷�һ����Ͷ��۸񲿷�һ���� 
 
             
 
