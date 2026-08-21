-- 疾病上报列表需要真实登记时间；历史输出同时保留审计记录，避免前端以临时状态伪造打印标识。
ALTER TABLE disease_report
    ADD COLUMN created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER reported_by,
    ADD KEY idx_disease_report_admission_created (admission_id, created_at);

CREATE TABLE disease_report_output_log (
    disease_report_output_log_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    disease_report_id INT UNSIGNED NOT NULL,
    output_type VARCHAR(16) NOT NULL,
    output_by INT UNSIGNED NOT NULL,
    output_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_disease_report_output (disease_report_id, output_type, output_at),
    CONSTRAINT fk_disease_report_output_report FOREIGN KEY (disease_report_id)
        REFERENCES disease_report(disease_report_id),
    CONSTRAINT fk_disease_report_output_user FOREIGN KEY (output_by)
        REFERENCES system_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
