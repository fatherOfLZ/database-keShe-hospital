package com.hospital.workstation;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
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
}
