---- 查人的人员职位关系表
SELECT
  peha.position_structure_id,
  pps.name,
  fndu.USER_NAME current_use,
  papf.FULL_NAME,
  peha.EMPLOYEE_ID,
  ppos.NAME,
  ppos.POSITION_ID,
  fndu2.USER_NAME superior_use,
  peha.SUPERIOR_LEVEL,
  papf2.FULL_NAME, 
  peha.SUPERIOR_ID,
  ppos2.POSITION_ID,
  ppos2.NAME
FROM
  PO_EMPLOYEE_HIERARCHIES_ALL peha,
  PER_POSITIONS ppos,
  PER_POSITIONS ppos2,
  PER_POSITION_STRUCTURES pps,
  per_all_people_f papf,
  per_all_people_f papf2,
  fnd_user fndu,
  fnd_user fndu2
WHERE
  fndu2.EMPLOYEE_ID = papf2.PERSON_ID and
  papf2.PERSON_ID = peha.SUPERIOR_ID and
  papf2.EFFECTIVE_END_DATE > sysdate and
  papf.PERSON_ID = peha.employee_id and
  papf.EFFECTIVE_END_DATE > sysdate and
  ppos2.POSITION_ID = peha.SUPERIOR_POSITION_ID and
  ppos.position_id = peha.EMPLOYEE_POSITION_ID and
  peha.superior_level >= 0 and
  peha.employee_id = fndu.EMPLOYEE_ID and
  peha.position_structure_id=pps.position_structure_id and
  fndu.USER_NAME = upper('&UserName')
ORDER BY peha.position_structure_id, peha.superior_level;




--人员与职务职位

SELECT DISTINCT fu.user_name
               ,emp.employee_id
               ,emp.full_name
               ,paf.job_id
               ,paf.position_id
               ,job.name        job_name
               ,positions.name  position_name
               ,job.BUSINESS_GROUP_ID
             ,emp.email_address
FROM   apps.hr_employees      emp
      ,apps.per_assignments_f paf
      ,apps.per_jobs          job
      ,apps.per_positions     positions
      ,apps.fnd_user          fu
WHERE  emp.employee_id = paf.person_id
AND    paf.job_id = job.job_id
and    job.BUSINESS_GROUP_ID=182   ---�̶�ֻ��ĳ����֯�Ĳ�����
AND    fu.employee_id = emp.employee_id
AND    paf.position_id = positions.position_id(+)
AND    SYSDATE BETWEEN nvl(paf.effective_start_date, SYSDATE) AND
       nvl(paf.effective_end_date, SYSDATE)
AND    SYSDATE BETWEEN nvl(fu.start_date, SYSDATE) AND
       nvl(fu.end_date, SYSDATE)
AND    SYSDATE BETWEEN nvl(job.date_from, SYSDATE) AND
       nvl(job.date_to, SYSDATE)
AND    SYSDATE BETWEEN nvl(positions.date_effective, SYSDATE) AND
       nvl(positions.date_end, SYSDATE);


--ְ有多少个职位层次
  SELECT DISTINCT PEHA.POSITION_STRUCTURE_ID, PPS.NAME
FROM PO_EMPLOYEE_HIERARCHIES_ALL PEHA
,PER_POSITION_STRUCTURES PPS
WHERE PEHA.POSITION_STRUCTURE_ID = PPS.POSITION_STRUCTURE_ID
order by PEHA.POSITION_STRUCTURE_ID;



----人员职员职位层次结构
select peh.BUSINESS_GROUP_ID,
       peh.ORG_ID,
       peh.EMPLOYEE_ID,
       pap.FIRST_NAME || pap.LAST_NAME || pap.FULL_NAME,
       peh.SUPERIOR_ID,
       peh.SUPERIOR_LEVEL,
       peh.POSITION_STRUCTURE_ID,
       peh.EMPLOYEE_POSITION_ID,
       peh.SUPERIOR_POSITION_ID
  from PO_EMPLOYEE_HIERARCHIES_ALL peh, PER_ALL_PEOPLE_F pap
 where peh.BUSINESS_GROUP_ID = 182
   and pap.PERSON_ID = peh.EMPLOYEE_ID

 order by peh.POSITION_STRUCTURE_ID, peh.SUPERIOR_LEVEL, peh.SUPERIOR_ID;

----
SELECT t.user_profile_option_name "Profile Option",
decode(a.level_id, 10001, 'Site',
10002, 'Application',
10003, 'Responsibility',
10004, 'User') "Level",
decode(a.level_id, 10001, 'Site',
10002, b.application_short_name,
10003, c.responsibility_name,
10004, d.user_name) "Level Value",
a.profile_option_value "Profile Value"
FROM fnd_profile_option_values a,
fnd_application b,
fnd_responsibility_tl c,
fnd_user d,
fnd_profile_options e,
fnd_profile_options_tl t
WHERE a.profile_option_id = e.profile_option_id
AND e.profile_option_name in ('ORG_ID', 'XLA_MO_SECURITY_PROFILE_LEVEL')
AND a.level_value = b.application_id(+)
AND a.level_value = c.responsibility_id(+)
AND a.level_value = d.user_id(+)
AND t.profile_option_name = e.profile_option_name
AND t.LANGUAGE = 'US'
ORDER BY e.profile_option_name, a.level_id DESC;
