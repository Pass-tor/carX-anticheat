CREATE TABLE IF NOT EXISTS `carxac_admin` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(128) NOT NULL,
  `player_name` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_carxac_admin_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `carxac_banlist` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `PLAYER_NAME` varchar(128) DEFAULT NULL,
  `STEAM` varchar(128) NOT NULL DEFAULT '__NONE__',
  `DISCORD` varchar(64) NOT NULL DEFAULT '__NONE__',
  `LICENSE` varchar(128) NOT NULL DEFAULT '__NONE__',
  `LIVE` varchar(128) NOT NULL DEFAULT '__NONE__',
  `XBL` varchar(128) NOT NULL DEFAULT '__NONE__',
  `IP` varchar(64) NOT NULL DEFAULT '__NONE__',
  `TOKENS` longtext NOT NULL,
  `BANID` bigint unsigned NOT NULL,
  `REASON` text NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_carxac_banid` (`BANID`),
  KEY `idx_carxac_license` (`LICENSE`),
  KEY `idx_carxac_discord` (`DISCORD`),
  KEY `idx_carxac_ip` (`IP`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `carxac_unban` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(128) NOT NULL,
  `player_name` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_carxac_unban_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `carxac_whitelist` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(128) NOT NULL,
  `player_name` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_carxac_whitelist_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;


CREATE TABLE IF NOT EXISTS `carxac_detections` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `player_name` varchar(128) DEFAULT NULL,
  `server_id` int DEFAULT NULL,
  `detection` varchar(255) NOT NULL,
  `details` text,
  `action` varchar(16) NOT NULL DEFAULT 'WARN',
  `severity` varchar(16) NOT NULL DEFAULT 'MEDIUM',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_carxac_det_time` (`created_at`),
  KEY `idx_carxac_det_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
