-- 入院记录采用通用字段加可选神经专科查体，正文仍保存至 medical_record.content_json。
UPDATE document_template
SET field_schema = JSON_ARRAY(
        '主诉', '现病史', '既往史', '个人史', '婚育/月经史', '家族史',
        '生命体征', '一般情况', '皮肤黏膜与浅表淋巴结', '头颈部', '心肺', '腹部',
        '泌尿生殖系统', '脊柱四肢', '神经系统查体（可选）', '辅助检查',
        '初步诊断', '诊断依据', '诊疗计划', '患者或家属意见'),
    due_hours = 24,
    updated_at = CURRENT_TIMESTAMP
WHERE document_code = 'ADMISSION_RECORD' AND document_category = 'DOCTOR';
