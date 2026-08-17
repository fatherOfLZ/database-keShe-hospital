-- 住院临床工作站增量结构：只追加课程演示所需字段和业务表，不修改既有住院核心表。
INSERT IGNORE INTO role (role_code, role_name, description)
VALUES ('NURSE', '护士', '维护本科室患者的护理评估、护理记录和生命体征');

-- MySQL 的 ALTER TABLE 不支持 ADD COLUMN IF NOT EXISTS；条件 SQL 使升级中断后可安全续跑。
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='id_type')=0, 'ALTER TABLE patient ADD COLUMN id_type VARCHAR(32) NOT NULL DEFAULT ''ID_CARD'' AFTER patient_no', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='nationality')=0, 'ALTER TABLE patient ADD COLUMN nationality VARCHAR(64) NULL AFTER ethnicity', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='occupation')=0, 'ALTER TABLE patient ADD COLUMN occupation VARCHAR(64) NULL AFTER nationality', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='registered_address')=0, 'ALTER TABLE patient ADD COLUMN registered_address VARCHAR(255) NULL AFTER birth_place', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='current_address')=0, 'ALTER TABLE patient ADD COLUMN current_address VARCHAR(255) NULL AFTER registered_address', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='postal_code')=0, 'ALTER TABLE patient ADD COLUMN postal_code VARCHAR(16) NULL AFTER current_address', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='patient' AND column_name='emergency_contact_relation')=0, 'ALTER TABLE patient ADD COLUMN emergency_contact_relation VARCHAR(32) NULL AFTER emergency_contact_name', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;

SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='admission' AND column_name='admission_source')=0, 'ALTER TABLE admission ADD COLUMN admission_source VARCHAR(32) NOT NULL DEFAULT ''OUTPATIENT'' AFTER admission_time', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='admission' AND column_name='admission_condition')=0, 'ALTER TABLE admission ADD COLUMN admission_condition VARCHAR(32) NULL AFTER admission_source', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='admission' AND column_name='admission_diagnosis_summary')=0, 'ALTER TABLE admission ADD COLUMN admission_diagnosis_summary VARCHAR(500) NULL AFTER admission_condition', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;
SET @column_sql = IF((SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='admission' AND column_name='insurance_snapshot')=0, 'ALTER TABLE admission ADD COLUMN insurance_snapshot VARCHAR(255) NULL AFTER insurance_type', 'SELECT 1');
PREPARE workstation_column_statement FROM @column_sql;
EXECUTE workstation_column_statement;
DEALLOCATE PREPARE workstation_column_statement;

ALTER TABLE medical_record
    ADD COLUMN document_code VARCHAR(64) NULL AFTER record_type,
    ADD COLUMN template_name VARCHAR(128) NULL AFTER title,
    ADD COLUMN content_json JSON NULL AFTER content,
    ADD COLUMN submitted_at DATETIME NULL AFTER recorded_at,
    ADD COLUMN signed_by INT UNSIGNED NULL AFTER signed_at,
    ADD COLUMN patient_opinion VARCHAR(500) NULL AFTER signed_by,
    ADD COLUMN void_reason VARCHAR(500) NULL AFTER patient_opinion,
    ADD KEY idx_record_admission_status (admission_id, status, record_type),
    ADD CONSTRAINT fk_record_signer FOREIGN KEY (signed_by) REFERENCES system_user(user_id);

ALTER TABLE vital_sign
    ADD COLUMN pain_score TINYINT UNSIGNED NULL AFTER spo2,
    ADD COLUMN consciousness VARCHAR(32) NULL AFTER pain_score,
    ADD COLUMN intake_ml DECIMAL(10,2) NULL AFTER consciousness,
    ADD COLUMN output_ml DECIMAL(10,2) NULL AFTER intake_ml;

CREATE TABLE bed_movement_history (
    movement_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    movement_type VARCHAR(32) NOT NULL,
    from_department_id INT UNSIGNED NULL,
    to_department_id INT UNSIGNED NULL,
    from_bed_id INT UNSIGNED NULL,
    to_bed_id INT UNSIGNED NULL,
    reason VARCHAR(500) NULL,
    operated_by INT UNSIGNED NOT NULL,
    moved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_bed_movement_admission_time (admission_id, moved_at),
    CONSTRAINT fk_movement_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_movement_from_dept FOREIGN KEY (from_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_movement_to_dept FOREIGN KEY (to_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_movement_from_bed FOREIGN KEY (from_bed_id) REFERENCES bed(bed_id),
    CONSTRAINT fk_movement_to_bed FOREIGN KEY (to_bed_id) REFERENCES bed(bed_id),
    CONSTRAINT fk_movement_user FOREIGN KEY (operated_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE document_template (
    template_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    document_code VARCHAR(64) NOT NULL,
    template_name VARCHAR(128) NOT NULL,
    document_category VARCHAR(32) NOT NULL DEFAULT 'DOCTOR',
    field_schema JSON NOT NULL,
    due_hours INT UNSIGNED NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    version_no INT NOT NULL DEFAULT 1,
    created_by INT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_template_code_version (document_code, version_no),
    CONSTRAINT fk_template_creator FOREIGN KEY (created_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE medical_record_revision (
    revision_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    record_id INT UNSIGNED NOT NULL,
    previous_record_id INT UNSIGNED NULL,
    revision_reason VARCHAR(500) NOT NULL,
    revised_by INT UNSIGNED NOT NULL,
    revised_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_revision_record FOREIGN KEY (record_id) REFERENCES medical_record(record_id),
    CONSTRAINT fk_revision_previous FOREIGN KEY (previous_record_id) REFERENCES medical_record(record_id),
    CONSTRAINT fk_revision_user FOREIGN KEY (revised_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE medical_record_audit (
    audit_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    record_id INT UNSIGNED NOT NULL,
    action_type VARCHAR(32) NOT NULL,
    action_detail VARCHAR(500) NULL,
    actor_id INT UNSIGNED NOT NULL,
    action_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_record_audit_record (record_id, action_at),
    CONSTRAINT fk_record_audit_record FOREIGN KEY (record_id) REFERENCES medical_record(record_id),
    CONSTRAINT fk_record_audit_user FOREIGN KEY (actor_id) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE care_order (
    care_order_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(32) NOT NULL UNIQUE,
    admission_id INT UNSIGNED NOT NULL,
    order_type VARCHAR(32) NOT NULL,
    order_class VARCHAR(16) NOT NULL,
    order_name VARCHAR(255) NOT NULL,
    dose VARCHAR(64) NULL,
    route VARCHAR(64) NULL,
    frequency VARCHAR(64) NULL,
    start_time DATETIME NULL,
    end_time DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'OPEN',
    instruction_text VARCHAR(500) NULL,
    ordered_by INT UNSIGNED NOT NULL,
    stopped_by INT UNSIGNED NULL,
    stopped_at DATETIME NULL,
    cancel_reason VARCHAR(500) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_care_order_admission_status (admission_id, status, order_type),
    CONSTRAINT fk_care_order_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_care_order_creator FOREIGN KEY (ordered_by) REFERENCES system_user(user_id),
    CONSTRAINT fk_care_order_stopper FOREIGN KEY (stopped_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE care_order_execution (
    execution_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    care_order_id INT UNSIGNED NOT NULL,
    execution_status VARCHAR(16) NOT NULL DEFAULT 'EXECUTED',
    executed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    executed_by INT UNSIGNED NOT NULL,
    result_note VARCHAR(500) NULL,
    CONSTRAINT fk_execution_order FOREIGN KEY (care_order_id) REFERENCES care_order(care_order_id),
    CONSTRAINT fk_execution_user FOREIGN KEY (executed_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE nursing_record (
    nursing_record_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    record_type VARCHAR(32) NOT NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    content TEXT NOT NULL,
    pain_score TINYINT UNSIGNED NULL,
    intake_ml DECIMAL(10,2) NULL,
    output_ml DECIMAL(10,2) NULL,
    recorded_by INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'SIGNED',
    KEY idx_nursing_record_admission_time (admission_id, recorded_at),
    CONSTRAINT fk_nursing_record_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_nursing_record_user FOREIGN KEY (recorded_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE surgery_application (
    surgery_application_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    surgery_name VARCHAR(255) NOT NULL,
    surgery_level VARCHAR(32) NULL,
    planned_at DATETIME NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    diagnosis_summary VARCHAR(500) NULL,
    risk_note VARCHAR(500) NULL,
    applied_by INT UNSIGNED NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_surgery_admission_status (admission_id, status),
    CONSTRAINT fk_surgery_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_surgery_user FOREIGN KEY (applied_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE consultation_request (
    consultation_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    target_department_id INT UNSIGNED NOT NULL,
    consultation_type VARCHAR(32) NOT NULL,
    request_reason VARCHAR(500) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    requested_by INT UNSIGNED NOT NULL,
    requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    response_text TEXT NULL,
    responded_by INT UNSIGNED NULL,
    responded_at DATETIME NULL,
    CONSTRAINT fk_consult_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_consult_department FOREIGN KEY (target_department_id) REFERENCES department(department_id),
    CONSTRAINT fk_consult_requester FOREIGN KEY (requested_by) REFERENCES system_user(user_id),
    CONSTRAINT fk_consult_responder FOREIGN KEY (responded_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clinical_pathway_template (
    pathway_template_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    pathway_code VARCHAR(32) NOT NULL UNIQUE,
    pathway_name VARCHAR(128) NOT NULL,
    diagnosis_hint VARCHAR(255) NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_by INT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pathway_template_creator FOREIGN KEY (created_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clinical_pathway_task_template (
    pathway_task_template_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    pathway_template_id INT UNSIGNED NOT NULL,
    day_no INT UNSIGNED NOT NULL,
    task_name VARCHAR(255) NOT NULL,
    task_type VARCHAR(32) NOT NULL DEFAULT 'CLINICAL',
    sort_no INT NOT NULL DEFAULT 1,
    CONSTRAINT fk_pathway_task_template FOREIGN KEY (pathway_template_id) REFERENCES clinical_pathway_template(pathway_template_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clinical_pathway_enrollment (
    enrollment_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    pathway_template_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    enrolled_by INT UNSIGNED NOT NULL,
    enrolled_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    withdrawn_reason VARCHAR(500) NULL,
    UNIQUE KEY uk_pathway_active_admission (admission_id, pathway_template_id),
    CONSTRAINT fk_enrollment_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_enrollment_template FOREIGN KEY (pathway_template_id) REFERENCES clinical_pathway_template(pathway_template_id),
    CONSTRAINT fk_enrollment_user FOREIGN KEY (enrolled_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clinical_pathway_task (
    pathway_task_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id INT UNSIGNED NOT NULL,
    day_no INT UNSIGNED NOT NULL,
    task_name VARCHAR(255) NOT NULL,
    task_type VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    completed_by INT UNSIGNED NULL,
    completed_at DATETIME NULL,
    variation_reason VARCHAR(500) NULL,
    CONSTRAINT fk_pathway_task_enrollment FOREIGN KEY (enrollment_id) REFERENCES clinical_pathway_enrollment(enrollment_id),
    CONSTRAINT fk_pathway_task_user FOREIGN KEY (completed_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE disease_report (
    disease_report_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    report_type VARCHAR(64) NOT NULL,
    disease_name VARCHAR(255) NOT NULL,
    report_content TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    reported_by INT UNSIGNED NOT NULL,
    reported_at DATETIME NULL,
    reviewed_by INT UNSIGNED NULL,
    reviewed_at DATETIME NULL,
    review_note VARCHAR(500) NULL,
    void_reason VARCHAR(500) NULL,
    KEY idx_disease_report_admission_status (admission_id, status),
    CONSTRAINT fk_disease_report_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_disease_report_creator FOREIGN KEY (reported_by) REFERENCES system_user(user_id),
    CONSTRAINT fk_disease_report_reviewer FOREIGN KEY (reviewed_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE disease_report_type (
    disease_report_type_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type_code VARCHAR(64) NOT NULL UNIQUE,
    type_name VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_by INT UNSIGNED NULL,
    CONSTRAINT fk_report_type_user FOREIGN KEY (created_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE report_attachment (
    attachment_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    report_id INT UNSIGNED NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    mime_type VARCHAR(128) NULL,
    uploaded_by INT UNSIGNED NOT NULL,
    uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_report_attachment_report FOREIGN KEY (report_id) REFERENCES exam_report(report_id),
    CONSTRAINT fk_report_attachment_user FOREIGN KEY (uploaded_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE export_task (
    export_task_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admission_id INT UNSIGNED NOT NULL,
    export_type VARCHAR(32) NOT NULL,
    source_id INT UNSIGNED NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING_TEMPLATE',
    message VARCHAR(500) NOT NULL DEFAULT '尚未配置正式 PDF 模板',
    requested_by INT UNSIGNED NOT NULL,
    requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_export_admission FOREIGN KEY (admission_id) REFERENCES admission(admission_id),
    CONSTRAINT fk_export_user FOREIGN KEY (requested_by) REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
