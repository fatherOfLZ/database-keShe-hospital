package com.hospital.workflow;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.hospital.admission.AdmissionService;
import com.hospital.clinical.ClinicalController;
import com.hospital.clinical.ClinicalService;
import com.hospital.common.BusinessException;
import com.hospital.security.JwtUser;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

/** 通过模拟数据库返回值验证核心事务在非法前置条件下会拒绝执行。 */
@ExtendWith(MockitoExtension.class)
class WorkflowServiceTest {
    private static final JwtUser ADMISSION_USER = new JwtUser(2L, "admission", "ADMISSION");
    private static final JwtUser DOCTOR_USER = new JwtUser(3L, "doctor", "DOCTOR");

    @Mock
    private JdbcTemplate jdbc;

    private AdmissionService admissionService;
    private ClinicalService clinicalService;

    @BeforeEach
    void setUp() {
        admissionService = new AdmissionService(jdbc);
        clinicalService = new ClinicalService(jdbc);
    }

    @Test
    void rejectsAdmissionWhenBedIsOccupied() {
        when(jdbc.queryForObject(contains("SELECT status FROM bed"), eq(String.class), eq(1L)))
                .thenReturn("OCCUPIED");

        assertThrows(
                BusinessException.class,
                () -> admissionService.admit(
                        1L,
                        1L,
                        3L,
                        1L,
                        "LEVEL_2",
                        "INSURED",
                        "居民医保",
                        ADMISSION_USER));
    }

    @Test
    void rejectsRefundBeyondAvailableDeposit() {
        when(jdbc.queryForObject(contains("SELECT status FROM admission"), eq(String.class), eq(1L)))
                .thenReturn("IN_HOSPITAL");
        when(jdbc.queryForObject(contains("FROM deposit_transaction"), eq(BigDecimal.class), eq(1L)))
                .thenReturn(new BigDecimal("100.00"));

        assertThrows(
                BusinessException.class,
                () -> admissionService.deposit(
                        1L,
                        "REFUND",
                        new BigDecimal("101.00"),
                        "CASH",
                        "测试退款",
                        ADMISSION_USER));
    }

    @Test
    void rejectsTransferWhenTargetBedIsUnavailable() {
        when(jdbc.queryForMap(contains("department_transfer"), eq(9L)))
                .thenReturn(Map.of("status", "PENDING", "to_bed_id", 8L));
        when(jdbc.queryForObject(contains("SELECT status FROM bed"), eq(String.class), eq(8L)))
                .thenReturn("OCCUPIED");

        assertThrows(BusinessException.class, () -> admissionService.approveTransfer(9L, ADMISSION_USER));
    }

    @Test
    void rejectsSettlementWhenDepositIsInsufficient() {
        when(jdbc.queryForMap(contains("current_bed_id,status FROM admission"), eq(1L)))
                .thenReturn(Map.of("current_bed_id", 1L, "status", "IN_HOSPITAL"));
        when(jdbc.queryForObject(contains("FROM charge WHERE"), eq(BigDecimal.class), eq(1L)))
                .thenReturn(new BigDecimal("200.00"));
        when(jdbc.queryForObject(contains("FROM deposit_transaction"), eq(BigDecimal.class), eq(1L)))
                .thenReturn(new BigDecimal("100.00"));

        assertThrows(BusinessException.class, () -> admissionService.settle(1L, ADMISSION_USER));
    }

    @Test
    void rejectsPrescriptionForInactiveDrug() {
        when(jdbc.queryForMap(contains("attending_doctor_id,status FROM admission"), eq(1L)))
                .thenReturn(Map.of("attending_doctor_id", 3L, "status", "IN_HOSPITAL"));
        when(jdbc.queryForObject(any(String.class), eq(Long.class))).thenReturn(7L);
        when(jdbc.queryForMap(contains("FROM drug"), eq(5L)))
                .thenReturn(Map.of("drug_name", "测试药品", "unit_price", BigDecimal.ONE, "status", "INACTIVE"));

        ClinicalController.PrescriptionItemRequest item = new ClinicalController.PrescriptionItemRequest(
                5L,
                BigDecimal.ONE,
                "片",
                "口服",
                "每日一次",
                1,
                1,
                null);

        assertThrows(
                BusinessException.class,
                () -> clinicalService.createPrescription(
                        1L,
                        "LONG_TERM",
                        LocalDateTime.now(),
                        null,
                        null,
                        List.of(item),
                        DOCTOR_USER));
    }

    @Test
    void rejectsReportForCancelledExamItem() {
        when(jdbc.queryForMap(contains("exam_order_item eoi"), eq(10L)))
                .thenReturn(Map.of("status", "CANCELLED", "admission_id", 1L));
        when(jdbc.queryForMap(contains("attending_doctor_id,status FROM admission"), eq(1L)))
                .thenReturn(Map.of("attending_doctor_id", 3L, "status", "IN_HOSPITAL"));

        assertThrows(
                BusinessException.class,
                () -> clinicalService.publishReport(
                        10L,
                        "测试报告",
                        "测试结论",
                        List.of(),
                        DOCTOR_USER));
    }
}
