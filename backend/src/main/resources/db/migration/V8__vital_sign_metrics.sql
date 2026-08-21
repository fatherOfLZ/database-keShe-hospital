-- 体征页需要独立展示心率与两类疼痛评分；身高、体重继续复用患者主档。
ALTER TABLE vital_sign
    ADD COLUMN heart_rate INT NULL AFTER pulse,
    ADD COLUMN analgesic_pain_score TINYINT UNSIGNED NULL AFTER pain_score,
    ADD COLUMN breakthrough_pain_score TINYINT UNSIGNED NULL AFTER analgesic_pain_score,
    ADD KEY idx_vital_sign_admission_measured_at (admission_id, measured_at);
