package com.hospital.admission;

import com.hospital.common.BusinessException;
import com.hospital.security.JwtUser;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 封装住院行政流程中必须保持一致的多表写操作。 */
@Service
public class AdmissionService {
    private final JdbcTemplate jdbc;

    public AdmissionService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 创建住院记录并将可用床位切换为占用状态。 */
    @Transactional
    public long admit(
            long patientId,
            long departmentId,
            Long doctorId,
            long bedId,
            String nursingLevel,
            String feeType,
            String insuranceType,
            JwtUser actor) {
        // 锁定床位后再创建住院记录，避免并发登记把同一张床分配给多名患者。
        String bedStatus = jdbc.queryForObject(
                "SELECT status FROM bed WHERE bed_id=? FOR UPDATE",
                String.class,
                bedId);
        if (!"AVAILABLE".equals(bedStatus)) {
            throw new BusinessException("床位当前不可分配");
        }

        Long exists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM patient WHERE patient_id=? AND status='ACTIVE'",
                Long.class,
                patientId);
        if (exists == null || exists == 0) {
            throw new BusinessException("患者不存在或已停用");
        }

        // 入院号和病案号基于登记时刻生成，保证演示系统中每次登记都可被独立追溯。
        String suffix = DateTimeFormatter.ofPattern("yyyyMMddHHmmssSSS")
                .format(LocalDateTime.now());
        // 入院记录保存本次住院的科室、床位和责任医师快照，后续转科不会覆盖入院来源。
        jdbc.update(
                "INSERT INTO admission(patient_id,inpatient_no,medical_record_no,admitting_department_id,"
                        + "current_department_id,attending_doctor_id,current_bed_id,admission_time,"
                        + "nursing_level,fee_type,insurance_type,status,created_by) "
                        + "VALUES (?,?,?,?,?,?,?,NOW(),?,?,?,?,?)",
                patientId,
                "IN" + suffix,
                "MR" + suffix,
                departmentId,
                departmentId,
                doctorId,
                bedId,
                nursingLevel,
                feeType,
                insuranceType,
                "IN_HOSPITAL",
                actor.userId());
        // 取得同一连接刚插入的主键，供调用方继续办理押金等后续操作。
        long admissionId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        // 仅在住院记录插入成功后标记床位占用；事务异常时两项修改会一起回滚。
        jdbc.update("UPDATE bed SET status='OCCUPIED' WHERE bed_id=?", bedId);
        // 入院也是一次床位流转，统一写入历史以便工作站完整回放患者在院位置。
        jdbc.update(
                "INSERT INTO bed_movement_history(admission_id,movement_type,to_department_id,to_bed_id,"
                        + "reason,operated_by) VALUES (?,'ADMISSION',?,?,?,?)",
                admissionId,
                departmentId,
                bedId,
                "入院分配床位",
                actor.userId());
        return admissionId;
    }

    /** 记录押金流水，并在退款前校验流水汇总后的可用余额。 */
    @Transactional
    public void deposit(
            long admissionId,
            String type,
            BigDecimal amount,
            String paymentMethod,
            String remark,
            JwtUser actor) {
        if (!type.equals("DEPOSIT") && !type.equals("REFUND") && !type.equals("REVERSAL")) {
            throw new BusinessException("不支持的押金流水类型");
        }

        // 押金余额由流水汇总，锁住住院记录可防止退款和结算同时修改余额。
        String status = jdbc.queryForObject(
                "SELECT status FROM admission WHERE admission_id=? FOR UPDATE",
                String.class,
                admissionId);
        if (!"IN_HOSPITAL".equals(status) && !"PENDING_DISCHARGE".equals(status)) {
            throw new BusinessException("当前住院状态不能处理押金");
        }

        BigDecimal balance = balance(admissionId);
        if ((type.equals("REFUND") || type.equals("REVERSAL")) && balance.compareTo(amount) < 0) {
            throw new BusinessException("退款金额超过可用押金余额");
        }

        // 每笔押金流水保存独立收据号，缴纳、退款和冲正均保留可审计记录。
        String receiptNo = "RC" + System.currentTimeMillis();
        jdbc.update(
                "INSERT INTO deposit_transaction(admission_id,txn_type,amount,payment_method,receipt_no,"
                        + "operator_id,remark) VALUES (?,?,?,?,?,?,?)",
                admissionId,
                type,
                amount,
                paymentMethod,
                receiptNo,
                actor.userId(),
                remark);
    }

    /** 保存转科申请，保留原科室和原床位作为历史轨迹。 */
    @Transactional
    public long requestTransfer(
            long admissionId,
            long toDepartmentId,
            Long toBedId,
            String reason,
            JwtUser actor) {
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT current_department_id,current_bed_id,status "
                        + "FROM admission WHERE admission_id=? FOR UPDATE",
                admissionId);
        if (!"IN_HOSPITAL".equals(admission.get("status"))) {
            throw new BusinessException("仅住院中的患者可以申请转科");
        }

        long currentDepartmentId = ((Number) admission.get("current_department_id")).longValue();
        if (currentDepartmentId == toDepartmentId) {
            throw new BusinessException("目标科室不能与当前科室相同");
        }

        // 申请阶段不改变在院患者的当前位置，等待住院处确认后才实际调床。
        jdbc.update(
                "INSERT INTO department_transfer(admission_id,from_department_id,to_department_id,"
                        + "from_bed_id,to_bed_id,requested_by,reason,status) "
                        + "VALUES (?,?,?,?,?,?,?,'PENDING')",
                admissionId,
                currentDepartmentId,
                toDepartmentId,
                admission.get("current_bed_id"),
                toBedId,
                actor.userId(),
                reason);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    /** 确认转科，保证床位状态、住院快照和转科记录同步提交。 */
    @Transactional
    public void approveTransfer(long transferId, JwtUser actor) {
        // 转科确认必须同时释放原床位、占用目标床位并更新住院快照，三个动作要么全成功要么全回滚。
        Map<String, Object> transfer = jdbc.queryForMap(
                "SELECT * FROM department_transfer WHERE transfer_id=? FOR UPDATE",
                transferId);
        if (!"PENDING".equals(transfer.get("status"))) {
            throw new BusinessException("该转科申请已处理");
        }

        Long targetBed = ((Number) transfer.get("to_bed_id")).longValue();
        String targetStatus = jdbc.queryForObject(
                "SELECT status FROM bed WHERE bed_id=? FOR UPDATE",
                String.class,
                targetBed);
        if (!"AVAILABLE".equals(targetStatus)) {
            throw new BusinessException("目标床位当前不可用");
        }

        long transferredAdmissionId = ((Number) transfer.get("admission_id")).longValue();
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT current_department_id,current_bed_id,status FROM admission WHERE admission_id=? FOR UPDATE",
                transferredAdmissionId);
        if (!"IN_HOSPITAL".equals(admission.get("status"))) {
            throw new BusinessException("患者当前不在院");
        }

        long currentBedId = ((Number) admission.get("current_bed_id")).longValue();
        // 先释放原床位，再占用目标床位；同一事务保证不会留下双占用或无床位的中间状态。
        jdbc.update("UPDATE bed SET status='AVAILABLE' WHERE bed_id=?", currentBedId);
        jdbc.update("UPDATE bed SET status='OCCUPIED' WHERE bed_id=?", targetBed);
        // 更新住院快照后，列表、费用和临床模块都将读取新的当前科室与床位。
        jdbc.update(
                "UPDATE admission SET current_department_id=?,current_bed_id=? WHERE admission_id=?",
                transfer.get("to_department_id"),
                targetBed,
                transferredAdmissionId);
        // 审批人和生效时间写入申请单，确保转科历史具备责任归属。
        jdbc.update(
                "UPDATE department_transfer SET status='APPROVED',approved_by=?,effective_time=NOW() "
                        + "WHERE transfer_id=?",
                actor.userId(),
                transferId);
        // 转科完成后写入不可变的位置轨迹，页面无需根据当前快照反推历史床位。
        jdbc.update(
                "INSERT INTO bed_movement_history(admission_id,movement_type,from_department_id,to_department_id,"
                        + "from_bed_id,to_bed_id,reason,operated_by) VALUES (?,'TRANSFER',?,?,?,?,?,?,?)",
                transferredAdmissionId,
                transfer.get("from_department_id"),
                transfer.get("to_department_id"),
                currentBedId,
                targetBed,
                transfer.get("reason"),
                actor.userId());
    }

    /** 结清未结费用并释放床位；押金不足时整个事务回滚。 */
    @Transactional
    public Map<String, BigDecimal> settle(long admissionId, JwtUser actor) {
        // 结算与出院、费用状态更新和床位释放属于一个业务原子操作。
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT current_department_id,current_bed_id,status FROM admission WHERE admission_id=? FOR UPDATE",
                admissionId);
        if (!"IN_HOSPITAL".equals(admission.get("status"))) {
            throw new BusinessException("仅住院中的患者可以结算出院");
        }

        // 结算总额只统计未结费用，历史已结费用不能重复参与本次扣款。
        BigDecimal total = jdbc.queryForObject(
                "SELECT COALESCE(SUM(amount),0) FROM charge WHERE admission_id=? AND status='UNSETTLED'",
                BigDecimal.class,
                admissionId);
        BigDecimal deposited = balance(admissionId);
        if (deposited.compareTo(total) < 0) {
            throw new BusinessException("押金不足，请先补缴 " + total.subtract(deposited));
        }

        // 押金覆盖总费用后的差额即为应退金额；本课程范围不支持欠费直接出院。
        BigDecimal refund = deposited.subtract(total);
        // 结算单固定保存本次总费用、使用押金和退款金额，避免之后的流水变化影响历史结算。
        jdbc.update(
                "INSERT INTO discharge_settlement(admission_id,total_charge,deposit_used,refund_amount,"
                        + "additional_payment,settled_at,settled_by,status) "
                        + "VALUES (?,?,?,?,?,NOW(),?,'SETTLED')",
                admissionId,
                total,
                total,
                refund,
                BigDecimal.ZERO,
                actor.userId());

        if (refund.compareTo(BigDecimal.ZERO) > 0) {
            // 有余额时额外生成退款流水，使押金账与结算单的退款金额相互可核对。
            jdbc.update(
                    "INSERT INTO deposit_transaction(admission_id,txn_type,amount,payment_method,"
                            + "receipt_no,operator_id,remark) VALUES (?,'REFUND',?,'CASH',?,?,?,'出院结算退款')",
                    admissionId,
                    refund,
                    "RC" + System.currentTimeMillis(),
                    actor.userId());
        }

        // 锁定全部本次费用，防止出院记录存在但收费项仍显示未结算。
        jdbc.update(
                "UPDATE charge SET status='SETTLED' WHERE admission_id=? AND status='UNSETTLED'",
                admissionId);
        // 出院时间和住院状态作为本次住院生命周期的最终状态。
        jdbc.update(
                "UPDATE admission SET status='DISCHARGED',discharge_time=NOW() WHERE admission_id=?",
                admissionId);
        // 只有上述结算数据写入完成后才释放床位，避免床位被提前重新分配。
        jdbc.update(
                "UPDATE bed SET status='AVAILABLE' WHERE bed_id=?",
                ((Number) admission.get("current_bed_id")).longValue());
        // 出院释放床位与结算在同一事务中完成，历史可准确反映床位被释放的时间点。
        jdbc.update(
                "INSERT INTO bed_movement_history(admission_id,movement_type,from_department_id,from_bed_id,"
                        + "reason,operated_by) VALUES (?,'DISCHARGE',?,?,?,?)",
                admissionId,
                admission.get("current_department_id"),
                admission.get("current_bed_id"),
                "出院结算后释放床位",
                actor.userId());

        return Map.of(
                "totalCharge", total,
                "depositUsed", total,
                "refundAmount", refund,
                "additionalPayment", BigDecimal.ZERO);
    }

    private BigDecimal balance(long admissionId) {
        // 押金余额始终由流水计算，不单独维护可变余额字段，以免出现账实不一致。
        return jdbc.queryForObject(
                "SELECT COALESCE(SUM(CASE WHEN txn_type='DEPOSIT' THEN amount ELSE -amount END),0) "
                        + "FROM deposit_transaction WHERE admission_id=?",
                BigDecimal.class,
                admissionId);
    }
}
