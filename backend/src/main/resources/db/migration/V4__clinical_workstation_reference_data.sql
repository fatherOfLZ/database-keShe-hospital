-- 参考工作站默认模板和临床路径，字段模式由 Flutter 表单按 JSON 逐项渲染。
INSERT INTO document_template (document_code, template_name, document_category, field_schema, due_hours, version_no)
VALUES
('ADMISSION_RECORD', '入院记录', 'DOCTOR', JSON_ARRAY('主诉', '现病史', '既往史', '体格检查', '初步诊断', '诊疗计划'), 24, 1),
('FIRST_COURSE', '首次病程记录', 'DOCTOR', JSON_ARRAY('病例特点', '诊断依据', '鉴别诊断', '诊疗计划'), 8, 1),
('DAILY_COURSE', '日常病程记录', 'DOCTOR', JSON_ARRAY('病情变化', '检查结果', '治疗调整', '上级医师意见'), 48, 1),
('CONSENT', '知情同意书', 'DOCTOR', JSON_ARRAY('告知事项', '替代方案', '风险说明', '患者意见'), 48, 1),
('PREOPERATIVE_SUMMARY', '术前小结', 'DOCTOR', JSON_ARRAY('术前诊断', '拟施手术', '术前准备', '风险评估'), 24, 1),
('POSTOPERATIVE_FIRST_COURSE', '术后首次病程记录', 'DOCTOR', JSON_ARRAY('术中情况', '术后诊断', '术后医嘱', '观察重点'), 24, 1),
('ANESTHESIA_PREOP_VISIT', '麻醉术前访视记录', 'DOCTOR', JSON_ARRAY('术前诊断', '拟施手术', '意识状态', '活动能力', '过敏史', '吸烟饮酒史', '系统疾病史', '麻醉手术史', '家族史', '生命体征', '辅助检查'), 24, 1),
('RESCUE_RECORD', '抢救记录', 'DOCTOR', JSON_ARRAY('抢救原因', '抢救经过', '参加人员', '抢救结果'), NULL, 1),
('TRANSFUSION_RECORD', '输血记录', 'DOCTOR', JSON_ARRAY('输血指征', '血液成分', '输血经过', '不良反应'), NULL, 1),
('DEATH_DISCUSSION', '死亡病例讨论记录', 'DOCTOR', JSON_ARRAY('死亡经过', '讨论意见', '死亡原因', '改进措施'), NULL, 1),
('DISCHARGE_RECORD', '出院记录', 'DOCTOR', JSON_ARRAY('入院诊断', '出院诊断', '住院经过', '出院医嘱', '随访建议'), NULL, 1),
('NURSING_ASSESSMENT', '护理评估单', 'NURSE', JSON_ARRAY('意识状态', '跌倒风险', '压疮风险', '营养风险', '护理措施'), 8, 1),
('ADULT_NURSING_RECORD', '成人护理记录', 'NURSE', JSON_ARRAY('病情观察', '护理措施', '出入量', '健康宣教'), NULL, 1);

INSERT INTO clinical_pathway_template (pathway_code, pathway_name, diagnosis_hint, status)
VALUES ('STROKE', '脑卒中住院临床路径', '脑梗死/脑出血', 'ACTIVE');

INSERT INTO disease_report_type (type_code, type_name, status)
VALUES ('DEATH_CARD', '死亡医学证明上报卡', 'ACTIVE'),
       ('INFECTIOUS', '传染病报告卡', 'ACTIVE');

INSERT INTO clinical_pathway_task_template (pathway_template_id, day_no, task_name, task_type, sort_no)
SELECT pathway_template_id, 1, '完成入院评估和首次病程记录', 'DOCUMENT', 1
FROM clinical_pathway_template WHERE pathway_code='STROKE';
INSERT INTO clinical_pathway_task_template (pathway_template_id, day_no, task_name, task_type, sort_no)
SELECT pathway_template_id, 1, '完成头颅影像检查申请', 'EXAM', 2
FROM clinical_pathway_template WHERE pathway_code='STROKE';
INSERT INTO clinical_pathway_task_template (pathway_template_id, day_no, task_name, task_type, sort_no)
SELECT pathway_template_id, 2, '复核生命体征和神经功能评分', 'NURSING', 3
FROM clinical_pathway_template WHERE pathway_code='STROKE';
INSERT INTO clinical_pathway_task_template (pathway_template_id, day_no, task_name, task_type, sort_no)
SELECT pathway_template_id, 3, '评估出院计划和康复宣教', 'CLINICAL', 4
FROM clinical_pathway_template WHERE pathway_code='STROKE';
