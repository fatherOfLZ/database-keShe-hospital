package com.hospital.clinical;

import com.hospital.common.ApiResponse;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 向医师开放开立医嘱所需的只读药品和检查检验目录。 */
@RestController
@RequestMapping("/api/v1/clinical/catalog")
@PreAuthorize("hasAnyRole('DOCTOR','SUPER_ADMIN')")
public class ClinicalCatalogController {
    private final JdbcTemplate jdbc;

    public ClinicalCatalogController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 返回可开立药品及当前目录价格；实际收费金额仍由服务层再次读取并快照。 */
    @GetMapping("/drugs")
    public ApiResponse<List<Map<String, Object>>> drugs() {
        return ApiResponse.ok(jdbc.queryForList(
                "SELECT drug_id,drug_code,drug_name,specification,unit,unit_price "
                        + "FROM drug WHERE status='ACTIVE' ORDER BY drug_code"));
    }

    /** 返回可开立检查检验项目及执行科室，供医师选择多个项目组成检查单。 */
    @GetMapping("/exam-items")
    public ApiResponse<List<Map<String, Object>>> examItems() {
        String sql = "SELECT e.exam_item_id,e.item_code,e.item_name,e.item_type,e.unit,e.reference_range,"
                + "e.unit_price,d.department_name FROM exam_item e "
                + "LEFT JOIN department d ON d.department_id=e.department_id "
                + "WHERE e.status='ACTIVE' ORDER BY e.item_code";
        return ApiResponse.ok(jdbc.queryForList(sql));
    }
}
