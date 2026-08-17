package com.hospital.clinical;

import com.hospital.common.BusinessException;
import com.hospital.security.JwtUser;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 医嘱、费用、报告等临床数据的事务服务。 */
@Service
public class ClinicalService {
    private final JdbcTemplate jdbc;

    public ClinicalService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void requireAccess(long admissionId, JwtUser actor) {
        // 读取责任医师与住院状态，作为所有临床写操作共用的数据范围校验依据。
        Map<String, Object> admission = jdbc.queryForMap(
                "SELECT attending_doctor_id,status FROM admission WHERE admission_id=?",
                admissionId);
        if (!"IN_HOSPITAL".equals(admission.get("status"))) {
            throw new BusinessException("患者当前未处于住院状态");
        }

        // 最高管理员可以审阅临床数据；普通医师仅能操作自己负责的住院患者。
        Object doctorId = admission.get("attending_doctor_id");
        boolean isDifferentAttendingDoctor = doctorId == null
                || ((Number) doctorId).longValue() != actor.userId();
        if ("DOCTOR".equals(actor.roleCode()) && isDifferentAttendingDoctor) {
            throw new BusinessException("只能维护本人负责患者的临床数据");
        }
    }

    /** 创建处方与明细，同时将每个药品的开立价格写入收费表。 */
    @Transactional
    public long createPrescription(
            long admissionId,
            String type,
            LocalDateTime start,
            LocalDateTime end,
            String remark,
            List<ClinicalController.PrescriptionItemRequest> items,
            JwtUser actor) {
        requireAccess(admissionId, actor);
        if (items == null || items.isEmpty()) {
            throw new BusinessException("处方至少应包含一个药品");
        }

        // 处方号按开立时刻生成，用于将处方主表、明细和费用来源关联起来。
        String prescriptionNo = "RX" + DateTimeFormatter.ofPattern("yyyyMMddHHmmssSSS")
                .format(LocalDateTime.now());
        jdbc.update(
                "INSERT INTO prescription(prescription_no,admission_id,doctor_id,prescription_type,"
                        + "start_time,end_time,status,remark) VALUES (?,?,?,?,?,?,'SUBMITTED',?)",
                prescriptionNo,
                admissionId,
                actor.userId(),
                type,
                start,
                end,
                remark);
        long prescriptionId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);

        // 药品价格会在开立时写入快照，后续目录调价不会篡改既有住院费用。
        for (ClinicalController.PrescriptionItemRequest item : items) {
            // 每个药品在写入处方前重新读取目录状态和当前价格，不能开立已停用药品。
            Map<String, Object> drug = jdbc.queryForMap(
                    "SELECT drug_name,unit_price,status FROM drug WHERE drug_id=?",
                    item.drugId());
            if (!"ACTIVE".equals(drug.get("status"))) {
                throw new BusinessException("药品已停用");
            }

            BigDecimal price = (BigDecimal) drug.get("unit_price");
            // 明细保存剂量、频次和单价快照，确保医嘱内容与计费依据可分别追溯。
            jdbc.update(
                    "INSERT INTO prescription_item(prescription_id,drug_id,dose,dose_unit,route,frequency,"
                            + "days,quantity,unit_price_snapshot,instruction_text) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    prescriptionId,
                    item.drugId(),
                    item.dose(),
                    item.doseUnit(),
                    item.route(),
                    item.frequency(),
                    item.days(),
                    item.quantity(),
                    price,
                    item.instruction());
            // 每种药品各自生成收费项，source_id 指向处方主表以支持费用来源追溯。
            jdbc.update(
                    "INSERT INTO charge(admission_id,source_type,source_id,item_name_snapshot,quantity,"
                            + "unit_price,amount,created_by) VALUES (?,?,?,?,?,?,?,?)",
                    admissionId,
                    "DRUG",
                    prescriptionId,
                    drug.get("drug_name"),
                    item.quantity(),
                    price,
                    price.multiply(BigDecimal.valueOf(item.quantity())),
                    actor.userId());
        }
        return prescriptionId;
    }

    /** 创建检查单、项目明细和对应收费记录。 */
    @Transactional
    public long createExamOrder(
            long admissionId,
            String priority,
            String note,
            List<Long> itemIds,
            JwtUser actor) {
        requireAccess(admissionId, actor);
        if (itemIds == null || itemIds.isEmpty()) {
            throw new BusinessException("至少选择一个检查检验项目");
        }

        // 检查单号作为多检查项目共享的父级业务编号。
        String orderNo = "EO" + DateTimeFormatter.ofPattern("yyyyMMddHHmmssSSS")
                .format(LocalDateTime.now());
        jdbc.update(
                "INSERT INTO exam_order(order_no,admission_id,doctor_id,priority,status,clinical_note) "
                        + "VALUES (?,?,?,?,'ORDERED',?)",
                orderNo,
                admissionId,
                actor.userId(),
                priority,
                note);
        long orderId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);

        // 每个执行项目都有独立状态和收费项，以支持部分出报告的情形。
        for (Long itemId : itemIds) {
            Map<String, Object> item = jdbc.queryForMap(
                    "SELECT item_name,unit_price,department_id,status FROM exam_item WHERE exam_item_id=?",
                    itemId);
            if (!"ACTIVE".equals(item.get("status"))) {
                throw new BusinessException("检查检验项目已停用");
            }

            // 项目明细记录实际执行科室与初始状态，报告可以按项目陆续产生。
            jdbc.update(
                    "INSERT INTO exam_order_item(exam_order_id,exam_item_id,execution_department_id,status) "
                            + "VALUES (?,?,?,'ORDERED')",
                    orderId,
                    itemId,
                    item.get("department_id"));
            long orderItemId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
            BigDecimal price = (BigDecimal) item.get("unit_price");
            // 检查项目按单项计费，目录价格在下单时固化为费用快照。
            jdbc.update(
                    "INSERT INTO charge(admission_id,source_type,source_id,item_name_snapshot,quantity,"
                            + "unit_price,amount,created_by) VALUES (?,?,?,?,1,?,?,?)",
                    admissionId,
                    "EXAM",
                    orderItemId,
                    item.get("item_name"),
                    price,
                    price,
                    actor.userId());
        }
        return orderId;
    }

    /** 发布检查报告、写入结果明细并刷新整张检查单的完成状态。 */
    @Transactional
    public void publishReport(
            long orderItemId,
            String name,
            String conclusion,
            List<ClinicalController.ResultRequest> results,
            JwtUser actor) {
        Map<String, Object> item = jdbc.queryForMap(
                "SELECT eoi.status,eo.admission_id FROM exam_order_item eoi "
                        + "JOIN exam_order eo ON eo.exam_order_id=eoi.exam_order_id "
                        + "WHERE eoi.exam_order_item_id=? FOR UPDATE",
                orderItemId);
        requireAccess(((Number) item.get("admission_id")).longValue(), actor);
        if ("CANCELLED".equals(item.get("status"))) {
            throw new BusinessException("已取消的项目不能录入报告");
        }

        // 报告主表保存结论，指标明细另表保存以支持一个检查项目有多个结果。
        jdbc.update(
                "INSERT INTO exam_report(exam_order_item_id,report_name,reported_by,conclusion,status) "
                        + "VALUES (?,?,?,?, 'PUBLISHED')",
                orderItemId,
                name,
                actor.userId(),
                conclusion);
        long reportId = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);

        for (ClinicalController.ResultRequest result : results) {
            // sort_no 保证前端按检验单既定顺序展示结果，而非依赖插入顺序。
            jdbc.update(
                    "INSERT INTO exam_result(report_id,item_name,qualitative_value,quantitative_value,unit,"
                            + "reference_range,abnormal_flag,remark,sort_no) VALUES (?,?,?,?,?,?,?,?,?)",
                    reportId,
                    result.itemName(),
                    result.qualitativeValue(),
                    result.quantitativeValue(),
                    result.unit(),
                    result.referenceRange(),
                    result.abnormalFlag(),
                    result.remark(),
                    result.sortNo());
        }

        // 项目出报告后，根据尚未出报告的项目数更新整张检查单状态。
        jdbc.update(
                "UPDATE exam_order_item SET status='REPORTED',executed_at=COALESCE(executed_at,NOW()) "
                        + "WHERE exam_order_item_id=?",
                orderItemId);
        // 从项目明细回查检查单，再判断这张单是否仍有未出报告项目。
        Long orderId = jdbc.queryForObject(
                "SELECT exam_order_id FROM exam_order_item WHERE exam_order_item_id=?",
                Long.class,
                orderItemId);
        Long outstanding = jdbc.queryForObject(
                "SELECT COUNT(*) FROM exam_order_item WHERE exam_order_id=? AND status<>'REPORTED'",
                Long.class,
                orderId);
        jdbc.update(
                "UPDATE exam_order SET status=? WHERE exam_order_id=?",
                outstanding == 0 ? "COMPLETED" : "PARTIAL_REPORTED",
                orderId);
    }
}
