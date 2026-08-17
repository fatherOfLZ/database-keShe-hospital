-- 病案首页诊断明细：四类诊断共用基础字段，按诊断类型选择性填写专有字段。
ALTER TABLE diagnosis
    ADD COLUMN predecessor VARCHAR(255) NULL COMMENT '诊断前体',
    ADD COLUMN diagnosis_note VARCHAR(500) NULL COMMENT '诊断补充说明',
    ADD COLUMN additional_code VARCHAR(64) NULL COMMENT '附加码',
    ADD COLUMN infectious_disease BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否传染病',
    ADD COLUMN body_position VARCHAR(32) NULL COMMENT '方位',
    ADD COLUMN body_site VARCHAR(128) NULL COMMENT '部位',
    ADD COLUMN t_stage VARCHAR(32) NULL COMMENT '肿瘤 T 分期',
    ADD COLUMN n_stage VARCHAR(32) NULL COMMENT '肿瘤 N 分期',
    ADD COLUMN m_stage VARCHAR(32) NULL COMMENT '肿瘤 M 分期',
    ADD COLUMN admission_condition VARCHAR(32) NULL COMMENT '入院病情',
    ADD COLUMN treated BOOLEAN NULL COMMENT '是否治疗',
    ADD COLUMN efficacy VARCHAR(128) NULL COMMENT '疗效',
    ADD COLUMN pathology_no VARCHAR(64) NULL COMMENT '病理号',
    ADD COLUMN tumor_diagnosis_basis VARCHAR(255) NULL COMMENT '肿瘤诊断依据',
    ADD COLUMN pathologist VARCHAR(64) NULL COMMENT '病理医师',
    ADD COLUMN pathology_technician VARCHAR(64) NULL COMMENT '病理技师';
