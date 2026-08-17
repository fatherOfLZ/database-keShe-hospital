package com.hospital;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Spring Boot 应用入口，负责装配 Web、JPA、Flyway 和安全组件。 */
@SpringBootApplication
public class HospitalApplication {
    public static void main(String[] args) {
        // 从 application 配置装配组件并启动嵌入式 Web 服务。
        SpringApplication.run(HospitalApplication.class, args);
    }
}
