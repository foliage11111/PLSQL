create or replace package ssq is

  -- Author  : ZR
  -- Created : 2016/4/8 16:51:40
  -- Purpose : 
procedure ssq_waijian
     (errbuf                             varchar2
     ,retcode                            number
     );
     
 procedure generate_foliage_ssq
     (errbuf                            out  varchar2
     ,retcode                           out  number
     );
     
   procedure zixunhuan(v_min number,v_max number); 
   procedure zhuxuanhuan(V_XH_ADD number);
   procedure zhuxuanhuan2(V_XH_ADD number);
   procedure chongtiankawei;
   procedure chongtiankawei2;

   procedure  insertT_SSQ_SHISHIKAWEI;          

end ssq;
/
create or replace package body ssq is

     procedure ssq_waijian
     (errbuf                             varchar2
     ,retcode                            number
     )
    is
                           
    --
    v_number number;
    v_r1 number;
    v_r2 number;
    v_r3 number;
    v_r4 number;
    v_r5 number;
    v_r6 number;
    v_b1 number;
    
   cursor c_ssb
   is
    select tss.num, tss.r1,tss.r2,tss.r3,tss.r4,tss.r5,tss.r6,tss.b1  from t_ssq_shishibiao tss 
    where   
  tss.num<2013168 and 
    tss.num>=2012101;
     
    --
    begin
     
     open c_ssb;
     Dbms_Output.put_line('��1  ��2  ��3  ��4  ��5  ��6  ��1');
     loop
       fetch c_ssb into v_number,v_r1,v_r2,v_r3,v_r4,v_r5,v_r6,v_b1;
    --  dbms_output.put_line(v_number);
       update t_ssq_shishibiao tss set tss.waijian=(
       select tssq.num from foliage_ssq tssq where
        tssq.r1=v_r1 and  tssq.r2=v_r2 and tssq.r3=v_r3 and tssq.r4=v_r4 
        and tssq.r5=v_r5 and tssq.r6=v_r6 and tssq.b1=v_b1 )
      where  tss.num=v_number;
       exit when c_ssb%notfound;
 
        end loop;
   close c_ssb;  
   commit;
         exception 
         when others then
           dbms_output.put_line(sqlerrm);   
       end ssq_waijian;
       

 procedure generate_foliage_ssq
     (errbuf                            out  varchar2
     ,retcode                           out  number
     )
     is
     --
     type t_tab is table of number index by pls_integer;
     A                                  t_tab;
     B                                  t_tab;
     v_num                              number := 6;  --j
     v_temp                             number;
     v_sum1                             number;
     v_sum2                             number;
     --
     begin
     --
       for i in 1..33 loop
          A(i) := i;
       end loop;
     --
       for i in 1..6 loop
          B(i) := i;
       end loop;
     --
       while B(1) < 33 loop
          --
          if B(v_num) = 33 then
             v_num := v_num - 1;
          end if;
          --
          B(v_num) := B(v_num) + 1;
          --
          for x in v_num+1..6 loop
             B(x) := B(v_num);
          end loop;
          --����
          v_temp := A(v_num);
          A(v_num) := A(B(v_num));
          A(B(v_num)) := v_temp;
          --
          v_sum1 := A(1)+A(2)+A(3)+A(4)+A(5)+A(6);
          
          for y in 1..16 loop
            v_sum2 := v_sum1+y; 
             insert into foliage_ssq values
             (foliage_seq.nextval
             ,A(1)
             ,A(2)
             ,A(3)
             ,A(4)
             ,A(5)
             ,A(6)
             ,y
             ,v_sum1
             ,v_sum2
             )
             ;
          end loop;
       end loop;
     end generate_foliage_ssq;       
 /*      
create sequence FOLIAGE_SEQ
minvalue 17721075
maxvalue 9999999999999
start with 19278420
increment by 1
cache 20;*/     



  procedure zhuxuanhuan2(V_XH_ADD number)
     is
     v_waixuanhuan number; 

    V_XH_SUM number;
 
    V_XH_MAX number;
 
    V_XH_MIN number;
 
    begin
  for i in  2012..2012  loop
      v_waixuanhuan:=i*1000;
   
      select max(ts.num) into V_XH_SUM from T_SSQ_SHISHIBIAO ts where ts.num<v_waixuanhuan+170 and ts.num>v_waixuanhuan;
     -- where ts.num <=320;
 
      V_XH_MIN:=v_waixuanhuan+131;  
      -- where ts.num<20XXOOO;  ѭ��ÿ��Ūһ��ÿ��������1����ts.num+1000
 
 --���ǳ����ˣ�2013001-2012001=1000 ����ʵ��ֻ��150�����ҡ�ÿ��Ҫ��������ÿ�θ���ÿ������ֵ������
      loop

       V_XH_MAX:=V_XH_MIN+V_XH_ADD;--ѭ������
 
      insertT_SSQ_SHISHIKAWEI ;

   
      V_XH_MIN:=V_XH_MAX;--�ı�ѭ������

 

      exit when V_XH_MIN>=V_XH_SUM;
       end loop;
        end loop;--end years loop
           exception 

 
        when others then
 
          dbms_output.put_line(sqlerrm);   

       end zhuxuanhuan2;          
 


procedure  insertT_SSQ_SHISHIKAWEI 
  is
    v_waijian                  number;
    type t_tab is table of number index by pls_integer;
v_jiou                     number;--��������
v_daxiao                   number;--��������
  
-----------------
v_weihe                    number;--β��
--v_weishugeshu              number;--β������

-----------------
v_lianhaogeshu             number;--���Ÿ���
v_l    number;--��������

-----------------
red_chonghaoshu            number;


v_shouweikuadu             number;--��β���

-----------------
 
v_area1                    number;--1��  1-11
v_area2                    number;--2��  12-22
v_area3                    number;--3��  23-33
v_temp                     number;--���ŵ���ʱ
 v_r                       t_tab;
  v2_r                       t_tab;
 ----
   v_bluetemp  number;
  v_bluecha   number;
  v_blue      number;
  v_bdx       number;
  v_bos       number;
  v_r12       number;
  v_r23       number;
  v_r34       number;
  v_r45       number;
  v_r56       number;

  cursor dtdq is select tsq.num,tsq.r1,tsq.r2,tsq.r3,tsq.r4,tsq.r5,tsq.r6,tsq.b1 
         from T_SSQ_SHISHIBIAO tsq where tsq.num >= 2012154 and tsq.num<=2013008 order by tsq.num;
                                                                                 --˳����©������

          begin
   
             open dtdq;
    dbms_output.put_line( '0 in  '||dtdq %ROWCOUNT);
              fetch   dtdq into v_waijian,v2_r(1),v2_r(2),v2_r(3),v2_r(4),v2_r(5),v2_r(6),v_bluetemp;
           
         dbms_output.put_line(v_waijian||'1 in  '||dtdq %ROWCOUNT);       
          loop    ---���LOOP�Ĵ����д����ɣ�����
            exit when dtdq%notfound;
         fetch dtdq into v_waijian,v_r(1),v_r(2),v_r(3),v_r(4),v_r(5),v_r(6),v_blue;
    dbms_output.put_line(v_waijian||'2 in  '||dtdq %ROWCOUNT);
           --   ��һ����Ҫ���¼���     -- v_jiou                     number;--ż������
                               v_jiou:=0;--д��ѭ��������Ա�֤ÿ��ѭ�����Զ���0
                           for i in 1..6 loop
                             if mod(v_r(i),2)=0 then
                               v_jiou:=v_jiou+1;
                               end if;
                                end loop;    
               
--v_daxiao                   number;--��������
                             v_daxiao:=0;
                             for i in 1..6 loop
                               if v_r(i)>16 then
                                 v_daxiao:=v_daxiao+1;
                               end if;
                             end loop;

----------------- 
--v_weihe                    number;--β��
--v_weishugeshu              number;--β������
                             v_weihe:=0;
                           for i in 1..6 loop
                             if v_r(i)>10 then
                           v_weihe:=v_weihe+mod(v_r(i),10);
                             end if;
                           end loop;
                            
-----------------
--v_lianhaogeshu             number;--���Ÿ���
 
                             v_lianhaogeshu:=0;
                         --    v_lianhaozushu:=0;
                             v_temp:=1;
                                 for i in 1..5 loop
                                 if v_r(i)+1=v_r(i+1) then
                                    v_temp:=v_temp+1;
                                    if v_lianhaogeshu<v_temp then 
                                       v_lianhaogeshu:=v_temp;
                                        end if;
                                    else
                                      v_temp:=1;
                                    
                                    end if;
                                      end loop;

-----------------
--v_area1                    number;--1��  1-11
--v_area2                    number;--2��  12-22
--v_area3                    number;--3��  23-33
--v_temp                     number;--���ŵ���ʱ
                             v_area1:=0;
                             v_area2:=0;
                             v_area3:=0;
                             for i in 1..6 loop
                               if v_r(i)<12 then
                                 v_area1:=v_area1+1;
                               
                                elsif   v_r(i)<23 then
                                v_area2:=v_area2+1;
                              
                                else
                                   v_area3:=v_area3+1;
                                   end if;
                --              dbms_output.put_line('v_area1 '||v_area1||' v_area2 '||v_area2||' v_area3 '||v_area3);  
                             end loop;
--v_shouweikuadu             number;--��β���
                             v_shouweikuadu:=v_r(6)-v_r(1);

                      
                v_r12:=v_r(2)- v_r(1);
                v_r23:=v_r(3)- v_r(2);
                v_r34:=v_r(4)- v_r(3);
                v_r45:=v_r(5)- v_r(4);
                v_r56:=v_r(6)- v_r(5);
                
                if mod(v_blue,2)=0 then
                  v_bos:=0;
                   else
                   v_bos:=1;
                  end if;
              --    v_bluetemp:=3; -- b1=3; ==>>select * from T_SSQ_SHISHIBIAO t  where t.num =2012130 
                if v_blue>8 then
                  v_bdx:=1;
                  else
                  v_bdx:=0;
                  end if;
                  v_bluecha:=v_blue-v_bluetemp;
                  v_bluetemp:=v_blue;
                  
               red_chonghaoshu:=0;   
                  for k in 1..6 loop
                    for j in  1..6 loop
                    if  v2_r(k)=v_r(j) then
                      red_chonghaoshu:=red_chonghaoshu+1;
                      end if;
                      end loop;
                  end loop;
                  
                  
         v2_r(1):=v_r(1);
          v2_r(2):= v_r(2);
           v2_r(3):= v_r(3);
            v2_r(4):= v_r(4);
             v2_r(5):= v_r(5);
              v2_r(6):= v_r(6);

               insert into T_SSQ_SHISHIKAWEI values
                    ( v_waijian 
                     ,v_jiou 
                       ,v_daxiao 
                       ,0--����
                         ,v_weihe
                         ,0--β��������ʵ���Ǵ���10�������߷�����
                           ,v_lianhaogeshu
                           ,red_chonghaoshu  --�غ��� ��Ҫ��
                           ,0  --��������
                             ,v_shouweikuadu
                               ,v_area1
                                 ,v_area2
                                   ,v_area3
                                   ,v_temp--red_lianhaozushu
                                   ,v_bos   ---blue_oushu
                                   ,v_bdx   ---blue_daxiao
                                   ,v_r12   ---red12
                                   ,v_r23   ---red23
                                   ,v_r34   ---red34
                                   ,v_r45   ---red45
                                   ,v_r56   ---red56
                                   ,v_bluecha   ---blue_gehaoshu
                                );
      
                     end loop;
 
           close dtdq;  
         
    exception 
         when others then
     dbms_output.put_line(sqlerrm);  
   end    insertT_SSQ_SHISHIKAWEI; 






       procedure zixunhuan(v_min number,v_max number)
    is
    v_waijian                  number;
    type t_tab is table of number index by pls_integer;
v_jiou                     number;--��������
v_daxiao                   number;--��������
  
-----------------
v_weihe                    number;--β��
--v_weishugeshu              number;--β������

-----------------
v_lianhaogeshu             number;--���Ÿ���
v_l    number;--��������

-----------------

v_shouweikuadu             number;--��β���

-----------------
 
v_area1                    number;--1��  1-11
v_area2                    number;--2��  12-22
v_area3                    number;--3��  23-33
v_temp                     number;--���ŵ���ʱ
 v_r                       t_tab;
 v2_r                       t_tab;

  cursor dtdq is select tsq.num,tsq.r1,tsq.r2,tsq.r3,tsq.r4,tsq.r5,tsq.r6,tsq.b1 
         from foliage_ssq tsq where tsq.num > v_min and tsq.num<=v_max;



--�����Ǹ��������� ����ǻ���������� ��ż ��С ���� β�� β������ ���Ÿ��� ��β��� 1������ 2������ 3������ 



          begin
             open dtdq;
             
         v2_r(1):=0;
          v2_r(2):=0;
           v2_r(3):=0;
            v2_r(4):=0;
             v2_r(5):=0;
              v2_r(6):=0;
         v_r(1):=0;
          v_r(2):=0;
           v_r(3):=0;
            v_r(4):=0;
             v_r(5):=0;
              v_r(6):=0;
            
          loop 
         fetch dtdq into v_waijian,v_r(1),v_r(2),v_r(3),v_r(4),v_r(5),v_r(6),v_temp;
      
     ---    dbms_output.put_line('NO.--'||v_l||' ' ||v_waijian || ' same red number '||v_temp);
         if v_r(1)=v2_r(1) and v_r(2)=v2_r(2) and v_r(3)=v2_r(3) and v_r(4)=v2_r(4) and v_r(5)=v2_r(5) and v_r(6)=v2_r(6)  then
           --  һ����ִ��һ�������� 
      --         dbms_output.put_line('red v2_r '||v2_r(1)||' '||v2_r(2)||' '||v2_r(3)||' '||v2_r(4)||' '
      --                     ||v2_r(5)||' '||v2_r(6));
               v_l:=0;
                      else 
           --   ��һ����Ҫ���¼���     -- v_jiou                     number;--ż������
                               v_jiou:=0;--д��ѭ��������Ա�֤ÿ��ѭ�����Զ���0
                           for i in 1..6 loop
                             if mod(v_r(i),2)=0 then
                               v_jiou:=v_jiou+1;
                               end if;
                                end loop;    
               
--v_daxiao                   number;--��������
                             v_daxiao:=0;
                             for i in 1..6 loop
                               if v_r(i)>16 then
                                 v_daxiao:=v_daxiao+1;
                               end if;
                             end loop;

----------------- 
--v_weihe                    number;--β��
--v_weishugeshu              number;--β������
                             v_weihe:=0;
                           for i in 1..6 loop
                             if v_r(i)>10 then
                           v_weihe:=v_weihe+mod(v_r(i),10);
                             end if;
                           end loop;
                            
-----------------
--v_lianhaogeshu             number;--���Ÿ���
 
                             v_lianhaogeshu:=0;
                         --    v_lianhaozushu:=0;
                             v_temp:=1;
                                 for i in 1..5 loop
                                 if v_r(i)+1=v_r(i+1) then
                                    v_temp:=v_temp+1;
                                    if v_lianhaogeshu<v_temp then 
                                       v_lianhaogeshu:=v_temp;
                                        end if;
                                    else
                                      v_temp:=1;
                                    
                                    end if;
                                      end loop;

-----------------
--v_area1                    number;--1��  1-11
--v_area2                    number;--2��  12-22
--v_area3                    number;--3��  23-33
--v_temp                     number;--���ŵ���ʱ
                             v_area1:=0;
                             v_area2:=0;
                             v_area3:=0;
                             for i in 1..6 loop
                               if v_r(i)<12 then
                                 v_area1:=v_area1+1;
                               
                                elsif   v_r(i)<23 then
                                v_area2:=v_area2+1;
                              
                                else
                                   v_area3:=v_area3+1;
                                   end if;
                --              dbms_output.put_line('v_area1 '||v_area1||' v_area2 '||v_area2||' v_area3 '||v_area3);  
                             end loop;
--v_shouweikuadu             number;--��β���
                             v_shouweikuadu:=v_r(6)-v_r(1);

                      
               insert into t_ssq_basickawei values
                    (foliage_seq.nextval  
                   ,v_waijian 
                     ,v_jiou 
                       ,v_daxiao 
                         ,v_weihe
                           ,v_lianhaogeshu
                             ,v_shouweikuadu
                               ,v_area1
                                 ,v_area2
                                   ,v_area3
                                   
                                );
                             
         /**     dbms_output.put_line('red number '||v_r(1)||' '||v_r(2)||' '||v_r(3)||' '||v_r(4)||' '
                            ||v_r(5)||' '||v_r(6)||' v_waijian'||v_waijian||' v_jiou'||v_jiou ||' v_daxiao'||v_daxiao
                             ||' v_weihe'||v_weihe ||' v_lianhaogeshu'|| v_lianhaogeshu||' v_shouweikuadu'||v_shouweikuadu ||' v_area1'||v_area1
                            ||' v_area2'||v_area2 ||' v_area3'||v_area3);   **/
                                end if;  --�����Ƿ���ͬ�����ݵ��ж���
                v2_r(1):=v_r(1);   --ֻ�и��������ݲ���Ҫ���¸�ֵ��v2_r ����Ļ���û�б�Ҫ�ظ���ô��
                  v2_r(2):=v_r(2);
                   v2_r(3):=v_r(3);
                    v2_r(4):=v_r(4);
                     v2_r(5):=v_r(5);
                      v2_r(6):=v_r(6);

             
                exit when dtdq%notfound;
 
                     end loop;
 
           close dtdq;  
           commit;
         exception 
       when others then
 
          dbms_output.put_line(sqlerrm);   
 
            end zixunhuan;

 

       procedure zhuxuanhuan(V_XH_ADD number)
     is
 
    V_XH_SUM number;
 
    V_XH_MAX number;
 
    V_XH_MIN number;
 
    begin
  
      select max(ts.num) into V_XH_SUM from foliage_ssq ts ;
     -- where ts.num <=320;
     -- where ts.num<20XXOOO;  ѭ��ÿ��Ūһ��ÿ��������1����ts.num+1000
      V_XH_MIN:=0;  
 --���ǳ����ˣ�2013001-2012001=1000 ����ʵ��ֻ��150�����ҡ�ÿ��Ҫ��������ÿ�θ���ÿ������ֵ������
      loop

       V_XH_MAX:=V_XH_MIN+V_XH_ADD;--ѭ������
 
      zixunhuan(V_XH_MIN,V_XH_MAX);

   
      V_XH_MIN:=V_XH_MAX;--�ı�ѭ������

 

      exit when V_XH_MIN>=V_XH_SUM;
       end loop;

           exception 

 
        when others then
 
          dbms_output.put_line(sqlerrm);   

       end zhuxuanhuan;          
 

       procedure chongtiankawei
  is
  cursor sskw is select ts2.num,ts2.r1,ts2.r2,ts2.r3,ts2.r4,ts2.r5,ts2.r6,ts2.b1 from t_ssq_shishibiao ts2  ;
  v_zhujian   number;
  v_bluetemp  number;
  v_bluecha   number;
  v_blue      number;
  v_bdx       number;
  v_bos       number;
  v_r12       number;
  v_r23       number;
  v_r34       number;
  v_r45       number;
  v_r56       number;
  v_r1        number;
  v_r2        number;
  v_r3        number;
  v_r4        number;
  v_r5        number;
  v_r6        number;
  
  begin
    v_bluetemp:=0;
                open sskw;
              loop 
                fetch sskw into v_zhujian,v_r1,v_r2,v_r3,v_r4,v_r5,v_r6,v_blue;
                v_r12:=v_r2-v_r1;
                v_r23:=v_r3-v_r2;
                v_r34:=v_r4-v_r3;
                v_r45:=v_r5-v_r4;
                v_r56:=v_r6-v_r5;
                
                if mod(v_blue,2)=0 then
                  v_bos:=0;
                   else
                   v_bos:=1;
                  end if;
                  
                if v_blue>8 then
                  v_bdx:=1;
                  else
                  v_bdx:=0;
                  end if;
                  v_bluecha:=v_blue-v_bluetemp;
                  v_bluetemp:=v_blue;
                  
              update t_ssq_shishikawei tssk2 set tssk2.blue_oushu=v_bos,tssk2.blue_daxiao=v_bdx,tssk2.red12=v_r12,
                     tssk2.red23=v_r23,tssk2.red34=v_r34,tssk2.red45=v_r45,tssk2.red56=v_r56, 
                     tssk2.blue_gehaoshu= v_bluecha where tssk2.zhujian=v_zhujian ;
                exit when sskw%notfound;
              end loop;
              
              close sskw;
      exception 
         when others then
     dbms_output.put_line(sqlerrm);   
end chongtiankawei;



       procedure chongtiankawei2
  is
  cursor ctkw2 is select 
  ssqb2.num,ssqb2.r1,ssqb2.r2,ssqb2.r3,ssqb2.r4,ssqb2.r5,ssqb2.r6 from t_ssq_shishibiao ssqb2;
  
  type t_tab is table of number index by pls_integer;
  v_zhujian  number;
  v_jishu    t_tab;
  v_oushu    number;
  begin
          open ctkw2;
          
          loop
            fetch ctkw2 into v_zhujian,v_jishu(1),v_jishu(2),v_jishu(3),v_jishu(4),v_jishu(5),v_jishu(6);
                  v_oushu:=0;      
              for i in 1..6 loop
                             if mod(v_jishu(i),2)=0 then
                               v_oushu:=v_oushu+1;
                               end if;
                                end loop;  
          update t_ssq_shishikawei tssss set tssss.red_oushu=v_oushu where tssss.zhujian=v_zhujian;
          
          exit when ctkw2%notfound;
            end loop;
            
            close ctkw2;
  
    exception 
         when others then
     dbms_output.put_line(sqlerrm);   
  
    end chongtiankawei2;
    
    
    
    
    
    
 


     
end ssq;
/
