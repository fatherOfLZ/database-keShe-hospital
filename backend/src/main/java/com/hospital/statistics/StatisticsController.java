package com.hospital.statistics;

import com.hospital.common.ApiResponse;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/statistics")
@PreAuthorize("hasAnyRole('SUPER_ADMIN','ADMISSION')")
/** 基于真实住院业务表汇总的课程演示统计接口。 */
public class StatisticsController {
    private final JdbcTemplate jdbc;

    public StatisticsController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/bed-occupancy")
    /** 统计科室床位总数、占用数和占用率。 */
    public ApiResponse<List<Map<String, Object>>> bedOccupancy() {
        // 使用 LEFT JOIN 保留尚未配置床位的科室；NULLIF 避免床位数为零时发生除零错误。
        String sql = "SELECT d.department_name,COUNT(b.bed_id) AS total_beds,"
                + "SUM(CASE WHEN b.status='OCCUPIED' THEN 1 ELSE 0 END) AS occupied_beds,"
                + "ROUND(SUM(CASE WHEN b.status='OCCUPIED' THEN 1 ELSE 0 END) "
                + "/NULLIF(COUNT(b.bed_id),0)*100,2) AS occupancy_rate "
                + "FROM department d LEFT JOIN ward w ON w.department_id=d.department_id "
                + "LEFT JOIN bed b ON b.ward_id=w.ward_id "
                + "GROUP BY d.department_id,d.department_name ORDER BY d.department_code";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @GetMapping("/diagnoses")
    /** 统计主要诊断对应的患者数和平均住院天数。 */
    public ApiResponse<List<Map<String, Object>>> diagnoses() {
        // 未出院患者以当前时间计算暂住天数，使统计能反映实时在院情况。
        String sql = "SELECT diagnosis_name,COUNT(*) AS patient_count,"
                + "ROUND(AVG(DATEDIFF(COALESCE(a.discharge_time,NOW()),a.admission_time)),1) "
                + "AS avg_stay_days FROM diagnosis d JOIN admission a ON a.admission_id=d.admission_id "
                + "WHERE d.is_primary=TRUE GROUP BY diagnosis_name ORDER BY patient_count DESC";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }

    @GetMapping("/charges")
    /** 按费用来源汇总药品和检查检验等支出。 */
    public ApiResponse<List<Map<String, Object>>> charges() {
        // 聚合收费表的金额快照，不依赖药品或检查目录的现行价格。
        String sql = "SELECT source_type,COUNT(*) AS item_count,SUM(amount) AS total_amount "
                + "FROM charge GROUP BY source_type ORDER BY total_amount DESC";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }
}
