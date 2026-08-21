package com.hospital.workstation;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.hospital.common.BusinessException;
import com.hospital.security.JwtUser;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

/** 验证工作站中不可逆的文书状态和管理员审核权限。 */
@ExtendWith(MockitoExtension.class)
class WorkstationServiceTest {
    private static final JwtUser DOCTOR = new JwtUser(3L, "doctor", "DOCTOR");
    private static final JwtUser ADMISSION = new JwtUser(2L, "admission", "ADMISSION");

    @Mock
    private JdbcTemplate jdbc;

    private WorkstationService service;

    @BeforeEach
    void setUp() {
        service = new WorkstationService(jdbc);
    }

    @Test
    void rejectsDocumentSubmissionWhenDocumentIsNotDraft() {
        when(jdbc.queryForObject(contains("FROM medical_record"), eq(Long.class), eq(8L)))
                .thenReturn(1L);
        when(jdbc.queryForMap(contains("FROM admission"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L));
        when(jdbc.update(contains("status='SUBMITTED'"), eq(8L))).thenReturn(0);

        assertThrows(BusinessException.class, () -> service.submitDocument(8L, DOCTOR));
    }

    @Test
    void rejectsDiseaseReportReviewByNonAdministrator() {
        assertThrows(
                BusinessException.class,
                () -> service.reviewDiseaseReport(9L, true, "通过", ADMISSION));
    }

    @Test
    void rejectsDiseaseReportOutputForAnotherAdmission() {
        when(jdbc.queryForMap(contains("FROM admission"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L, "current_department_id", 1L));
        when(jdbc.queryForObject(contains("FROM disease_report"), eq(Long.class), eq(9L), eq(1L)))
                .thenReturn(0L);

        assertThrows(
                BusinessException.class,
                () -> service.recordDiseaseReportOutput(1L, java.util.List.of(9L), "PRINT", DOCTOR));
    }

    @Test
    void writesDiseaseReportOutputAuditForAccessibleRecord() {
        when(jdbc.queryForMap(contains("FROM admission"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L, "current_department_id", 1L));
        when(jdbc.queryForObject(contains("FROM disease_report"), eq(Long.class), eq(9L), eq(1L)))
                .thenReturn(1L);

        service.recordDiseaseReportOutput(1L, java.util.List.of(9L), "PRINT", DOCTOR);

        verify(jdbc).update(
                contains("INSERT INTO disease_report_output_log"),
                eq(9L), eq("PRINT"), eq(3L));
    }

    @Test
    void rejectsOutpatientVisitFromAnotherPatient() {
        when(jdbc.queryForMap(contains("FROM admission"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L));
        when(jdbc.queryForObject(contains("FROM outpatient_visit"), eq(Long.class), eq(8L), eq(1L)))
                .thenReturn(0L);

        assertThrows(
                BusinessException.class,
                () -> service.requireOutpatientVisitReadAccess(1L, 8L, DOCTOR));
    }

    @Test
    void rejectsCreatingSecondCurrentAdmissionRecord() {
        when(jdbc.queryForMap(contains("SELECT status,attending_doctor_id"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L));
        when(jdbc.queryForMap(contains("FROM document_template"), eq(4L)))
                .thenReturn(Map.of("template_name", "入院记录", "document_code", "ADMISSION_RECORD"));
        when(jdbc.queryForObject(contains("FOR UPDATE"), eq(Long.class), eq(1L)))
                .thenReturn(1L);
        when(jdbc.queryForObject(contains("document_code='ADMISSION_RECORD'"), eq(Long.class), eq(1L)))
                .thenReturn(1L);

        assertThrows(
                BusinessException.class,
                () -> service.saveDocument(
                        1L,
                        4L,
                        "ADMISSION_RECORD",
                        "入院记录",
                        "入院记录",
                        "{}",
                        DOCTOR));
    }

    @Test
    void rejectsDirectUpdateAfterAdmissionRecordWasSigned() {
        when(jdbc.queryForMap(contains("FROM medical_record"), eq(12L)))
                .thenReturn(Map.of("admission_id", 1L, "status", "SIGNED"));
        when(jdbc.queryForMap(contains("SELECT status,attending_doctor_id"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L));

        assertThrows(
                BusinessException.class,
                () -> service.updateDocument(12L, "入院记录", "修订内容", "{}", DOCTOR));
    }

    @Test
    void updatesDraftAndWritesAuditTrail() {
        when(jdbc.queryForMap(contains("FROM medical_record"), eq(13L)))
                .thenReturn(Map.of("admission_id", 1L, "status", "DRAFT"));
        when(jdbc.queryForMap(contains("SELECT status,attending_doctor_id"), eq(1L)))
                .thenReturn(Map.of("status", "IN_HOSPITAL", "attending_doctor_id", 3L));
        when(jdbc.update(contains("UPDATE medical_record SET title"),
                eq("入院记录"), eq("更新后的内容"), eq("{}"), eq(13L)))
                .thenReturn(1);

        service.updateDocument(13L, "入院记录", "更新后的内容", "{}", DOCTOR);

        verify(jdbc).update(
                contains("INSERT INTO medical_record_audit"),
                eq(13L), eq("UPDATE"), eq("更新文书草稿"), eq(3L));
    }
}
