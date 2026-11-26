--
-- Luminum Server Database Schema
-- by Christopher R. Curzio (ccurzio@luminum.net)
--
-- Idempotent: safe to re-apply. Uses CREATE ... IF NOT EXISTS so re-running
-- the installer never drops existing data.
--
-- Updated 2026-11-03 from the production MariaDB 10.11 dump
-- (databases, tables, and column definitions below match that dump; the
-- dump's DROP TABLE statements and AUTO_INCREMENT counters were converted
-- to the idempotent form used by the installer).
--
-- Databases:
--   AUTH        web console accounts, 2FA, groups, sessions, prefs
--   CLIENTS     registered client identities and status
--   CONTENT     content sets, packages, sensors, history
--   DISCOVERY   discovery configuration
--   INTEGRITY   integrity watch/ignore lists, permissions
--   INVENTORY   (reserved)
--   LOGS        auth and system logs
--   POLICY      (reserved)
--   QUERY       query questions
--   SUMMARY     (reserved)
--   SYSTEM      server configuration, CPU history
--

--
-- Current Database: `POLICY`
--

CREATE DATABASE IF NOT EXISTS `POLICY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `POLICY`;

--
-- Current Database: `DISCOVERY`
--

CREATE DATABASE IF NOT EXISTS `DISCOVERY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `DISCOVERY`;

--
-- Table structure for table `CONFIG`
--

CREATE TABLE IF NOT EXISTS `CONFIG` (
  `ID` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `CONTENT`
--

CREATE DATABASE IF NOT EXISTS `CONTENT` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `CONTENT`;

--
-- Table structure for table `CATEGORIES`
--

CREATE TABLE IF NOT EXISTS `CATEGORIES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `CSID` int(20) NOT NULL,
  `NAME` tinytext NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `PACKAGES`
--

CREATE TABLE IF NOT EXISTS `PACKAGES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `DESCRIPTION` tinytext NOT NULL,
  `CSET` int(20) DEFAULT NULL,
  `SIZE` tinytext DEFAULT NULL,
  `MAC` tinyint(1) NOT NULL DEFAULT 0,
  `LIN` tinyint(1) NOT NULL DEFAULT 0,
  `WIN` tinyint(1) NOT NULL DEFAULT 0,
  `AUTHOR` int(20) NOT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  `REVISIONS` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `FILES`
--
-- File repository catalog (docs/p2p.md, Phase 0 "Repository model"). One
-- row per content-addressed blob stored under <install root>/content/files/
-- {aa}/{bb}/{sha256}. Files arrive via an ingestion vector (http chunked
-- upload, nfs, or smb drop into content/staging/{vector}/) and are
-- registered by the broker's discovery scan. A file is cataloged, not
-- authorized: it becomes distributable only when attached to a package
-- (PKGFILES). VIA is the vector's name; the column is not called VECTOR
-- because MariaDB 11.7+ reserves that word for the vector data type.
--

CREATE TABLE IF NOT EXISTS `FILES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `SHA256` char(64) NOT NULL,
  `SIZE` bigint(20) NOT NULL,
  `NAME` tinytext NOT NULL,
  `VIA` tinytext NOT NULL,
  `STAGED` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UQ_FILES_SHA` (`SHA256`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `UPLOADS`
--
-- In-flight chunked HTTP uploads (docs/p2p.md, Phase 0). The console API
-- (api/upload.php) appends raw chunk POSTs to
-- content/staging/http/.up-{ID}.part and tracks progress here; on finish
-- the temp file is renamed into the staging directory and the discovery
-- scan registers it like any other drop. Abandoned sessions are swept by
-- the same scan.
--

CREATE TABLE IF NOT EXISTS `UPLOADS` (
  `ID` char(36) NOT NULL,
  `NAME` tinytext NOT NULL,
  `SIZE` bigint(20) NOT NULL,
  `RECEIVED` bigint(20) NOT NULL DEFAULT 0,
  `VIA` tinytext NOT NULL DEFAULT 'http',
  `CREATED` datetime NOT NULL,
  `DONE` datetime DEFAULT NULL,
  PRIMARY KEY (`ID`),
  KEY `IDX_UPLOADS_CREATED` (`CREATED`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `PKGFILES`
--
-- Package attachment (docs/p2p.md, Phase 0): links a repository file
-- (FILES.ID) into a package (PACKAGES.ID) for one OS, with the file's
-- relative install path inside the package. Size and hash come from
-- FILES.
--

CREATE TABLE IF NOT EXISTS `PKGFILES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `PKGID` int(20) NOT NULL,
  `OS` tinytext NOT NULL,
  `FILEID` int(20) NOT NULL,
  `PATH` tinytext NOT NULL,
  PRIMARY KEY (`ID`),
  KEY `IDX_PKGFILES_PKG` (`PKGID`),
  KEY `IDX_PKGFILES_FILE` (`FILEID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `PKGHOLDERS`
--
-- P2P holder tracking (docs/p2p.md 7.3, Phase 1): which endpoints currently
-- hold which repository files. The broker upserts a row when a client
-- reports p2p_fetch_ok (or p2p/have at startup) and deletes an endpoint's
-- rows on deregistration and the missing sweep. A holder is a P2P source
-- candidate for the same file's next deploy (docs/p2p.md 7.1). SOURCE is
-- 'server' (seeded from the server), 'local' (the client's own prior
-- install), or the serving peer's UID.
--

CREATE TABLE IF NOT EXISTS `PKGHOLDERS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `FILEID` int(20) NOT NULL,
  `UID` int(20) NOT NULL,
  `SOURCE` tinytext NOT NULL,
  `TS` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UQ_PKGHOLDERS` (`FILEID`,`UID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SENSORHISTORY`
--

CREATE TABLE IF NOT EXISTS `SENSORHISTORY` (
  `ID` int(20) NOT NULL,
  `REV` int(20) NOT NULL,
  `NAME` tinytext NOT NULL,
  `DESCRIPTION` tinytext NOT NULL,
  `CSET` int(20) NOT NULL,
  `CATEGORY` int(20) DEFAULT NULL,
  `TIMEOUT` tinytext NOT NULL DEFAULT '2M',
  `MSTYPE` tinytext DEFAULT NULL,
  `MSCRIPT` mediumtext DEFAULT NULL,
  `LSTYPE` tinytext DEFAULT NULL,
  `LSCRIPT` mediumtext DEFAULT NULL,
  `WSTYPE` tinytext DEFAULT NULL,
  `WSCRIPT` mediumtext DEFAULT NULL,
  `RTYPE` tinytext NOT NULL,
  `USECASE` tinyint(1) NOT NULL DEFAULT 0,
  `CSPLIT` tinyint(1) NOT NULL DEFAULT 0,
  `DELIMITER` tinytext DEFAULT NULL,
  `OUTCOLS` tinytext DEFAULT NULL,
  `WITHPARAMS` tinyint(1) NOT NULL DEFAULT 0,
  `TIMESTAMP` datetime NOT NULL,
  `EDITOR` int(20) NOT NULL,
  UNIQUE KEY `SENSOR_REV` (`ID`, `REV`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SENSORPARAMS`
--

CREATE TABLE IF NOT EXISTS `SENSORPARAMS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `SID` int(20) NOT NULL,
  `FIELD` tinytext NOT NULL,
  `TYPE` tinytext NOT NULL,
  `VALOPTS` tinytext NOT NULL,
  `DEFAULTVAL` tinytext DEFAULT NULL,
  `HELPTEXT` tinytext DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SENSORS`
--

CREATE TABLE IF NOT EXISTS `SENSORS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `DESCRIPTION` tinytext NOT NULL,
  `CSET` int(20) NOT NULL,
  `CATEGORY` int(20) DEFAULT NULL,
  `TIMEOUT` tinytext NOT NULL DEFAULT '2M',
  `MSTYPE` tinytext DEFAULT NULL,
  `MSCRIPT` mediumtext DEFAULT NULL,
  `LSTYPE` tinytext DEFAULT NULL,
  `LSCRIPT` mediumtext DEFAULT NULL,
  `WSTYPE` tinytext DEFAULT NULL,
  `WSCRIPT` mediumtext DEFAULT NULL,
  `RTYPE` tinytext NOT NULL DEFAULT 'text',
  `USECASE` tinyint(1) NOT NULL DEFAULT 0,
  `CSPLIT` tinyint(1) NOT NULL DEFAULT 0,
  `DELIMITER` tinytext DEFAULT NULL,
  `OUTCOLS` tinytext DEFAULT NULL,
  `WITHPARAMS` tinyint(1) NOT NULL DEFAULT 0,
  `AUTHOR` int(20) NOT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SETS`
--

CREATE TABLE IF NOT EXISTS `SETS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `DESCRIPTION` tinytext NOT NULL,
  `REQUIRED` tinyint(1) NOT NULL,
  `LOCKED` tinyint(1) NOT NULL DEFAULT 0,
  `OWNER` int(20) DEFAULT NULL,
  `CREATED` datetime DEFAULT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `QUERY`
--

CREATE DATABASE IF NOT EXISTS `QUERY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `QUERY`;

--
-- Table structure for table `QUESTIONS`
--

CREATE TABLE IF NOT EXISTS `QUESTIONS` (
  `ID` int(20) NOT NULL,
  `QUESTION` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `INTEGRITY`
--

CREATE DATABASE IF NOT EXISTS `INTEGRITY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `INTEGRITY`;

--
-- Table structure for table `CONFIG`
--

CREATE TABLE IF NOT EXISTS `CONFIG` (
  `ID` int(20) NOT NULL,
  `MODE` tinyint(4) NOT NULL,
  `ENABLED` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `IGNORELIST`
--

CREATE TABLE IF NOT EXISTS `IGNORELIST` (
  `ID` int(20) NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `PERMISSIONS`
--

CREATE TABLE IF NOT EXISTS `PERMISSIONS` (
  `UID` tinytext NOT NULL,
  `ACCESS` tinyint(4) NOT NULL DEFAULT 1,
  `MANAGE_MODULE` tinyint(4) NOT NULL DEFAULT 0,
  `MANAGE_CLIENTS` tinyint(4) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `WATCHLIST`
--

CREATE TABLE IF NOT EXISTS `WATCHLIST` (
  `ID` int(20) NOT NULL,
  `OS` tinytext NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `WATCH_DEFAULT`
--

CREATE TABLE IF NOT EXISTS `WATCH_DEFAULT` (
  `OS` tinytext NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `SUMMARY`
--

CREATE DATABASE IF NOT EXISTS `SUMMARY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `SUMMARY`;

--
-- Current Database: `INVENTORY`
--

CREATE DATABASE IF NOT EXISTS `INVENTORY` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `INVENTORY`;

--
-- Current Database: `AUTH`
--

CREATE DATABASE IF NOT EXISTS `AUTH` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `AUTH`;

--
-- Table structure for table `2FA`
--

CREATE TABLE IF NOT EXISTS `2FA` (
  `UID` int(20) NOT NULL,
  `METHOD` tinytext NOT NULL,
  `AUTHDATA` tinytext NOT NULL,
  `ENABLED` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `GROUPS`
--

CREATE TABLE IF NOT EXISTS `GROUPS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `AUTHOR` int(20) DEFAULT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SESSION`
--

CREATE TABLE IF NOT EXISTS `SESSION` (
  `ID` int(20) NOT NULL,
  `SID` tinytext NOT NULL,
  `START` timestamp NOT NULL,
  `EXPIRES` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `USERPREFS`
--

CREATE TABLE IF NOT EXISTS `USERPREFS` (
  `ID` int(20) NOT NULL,
  `PREFKEY` tinytext NOT NULL,
  `PREFVAL` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `USERS`
--

CREATE TABLE IF NOT EXISTS `USERS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `USERNAME` tinytext NOT NULL,
  `FULLNAME` tinytext NOT NULL,
  `PASSWORD` tinytext NOT NULL,
  `EMAIL` tinytext DEFAULT NULL,
  `PHONE` tinytext NOT NULL,
  `TYPE` tinytext NOT NULL,
  `ROLE` tinyint(4) DEFAULT NULL,
  `REGDATE` datetime NOT NULL,
  `LASTSEEN` datetime DEFAULT NULL,
  `ENABLED` tinyint(4) NOT NULL DEFAULT 1,
  `CHANGEPASS` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `SYSTEM`
--

CREATE DATABASE IF NOT EXISTS `SYSTEM` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `SYSTEM`;

--
-- Table structure for table `CONFIG`
--

CREATE TABLE IF NOT EXISTS `CONFIG` (
  `CKEY` tinytext NOT NULL,
  `CVAL` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Default rows for table `CONFIG`
--
-- PASSKEYS (PassKey login support, console Server Options) defaults to
-- Disabled. CKEY carries no key, so the insert is guarded with NOT
-- EXISTS to stay idempotent across installer re-runs - a value later
-- changed in the console must survive.
--

INSERT INTO `CONFIG` (`CKEY`, `CVAL`)
SELECT 'PASSKEYS', 'Disabled' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `CONFIG` WHERE `CKEY` = 'PASSKEYS');

--
-- Table structure for table `CPUHIST`
--

CREATE TABLE IF NOT EXISTS `CPUHIST` (
  `TIMESTAMP` datetime DEFAULT NULL,
  `PCT` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `MEMHIST`
--

CREATE TABLE IF NOT EXISTS `MEMHIST` (
  `TIMESTAMP` datetime DEFAULT NULL,
  `PCT` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `CLIENTS`
--

CREATE DATABASE IF NOT EXISTS `CLIENTS` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `CLIENTS`;

--
-- Table structure for table `AUTH`
--

CREATE TABLE IF NOT EXISTS `AUTH` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `UUID` char(36) DEFAULT NULL,
  `FINGERPRINT` tinytext NOT NULL,
  `PUBKEY` text NOT NULL,
  `MQTTSECRET` char(64) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `GROUPS`
--

CREATE TABLE IF NOT EXISTS `GROUPS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `AUTHOR` int(20) DEFAULT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `STATUS`
--

CREATE TABLE IF NOT EXISTS `STATUS` (
  `ID` int(20) NOT NULL,
  `HOSTNAME` tinytext NOT NULL,
  `IPV4` tinytext NOT NULL,
  `IPV6` tinytext DEFAULT NULL,
  `OSPLATFORM` tinytext NOT NULL,
  `OSRELEASE` tinytext NOT NULL,
  `CLIENTVER` tinytext NOT NULL,
  `CSTATE` tinytext NOT NULL,
  `INGROUPS` text DEFAULT NULL,
  `REGDATE` datetime NOT NULL,
  `LASTSEEN` datetime DEFAULT NULL,
  `MISSING` tinyint(1) DEFAULT 0,
  `P2P` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `COMMANDS`
--
-- Outbox of server->client MQTT commands (protocol 4.2, 9). The broker's
-- MQTT worker publishes each PENDING row to its target topic and marks it
-- SENT; a matching client response marks it ACKED. TARGET is a numeric UID,
-- "all", "os/{os}", or "grp/{name}". QID is the envelope message id (reused
-- on retry so the client deduplicates a redelivered command).
--

CREATE TABLE IF NOT EXISTS `COMMANDS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `SID` tinytext NOT NULL,
  `TARGET` tinytext NOT NULL,
  `LUMY` tinytext NOT NULL,
  `ACTION` tinytext NOT NULL,
  `DATA` text DEFAULT NULL,
  `QID` char(36) NOT NULL,
  `STATUS` tinytext NOT NULL DEFAULT 'PENDING',
  `CREATED` datetime NOT NULL,
  `SENT` datetime DEFAULT NULL,
  `ACKED` datetime DEFAULT NULL,
  `DEADLINE` datetime DEFAULT NULL,
  PRIMARY KEY (`ID`),
  KEY `IDX_COMMANDS_STATUS` (`STATUS`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `DEREGS`
--
-- Queue of console-initiated endpoint deregistrations (protocol 6.1). The
-- console's Deregister action inserts a PENDING row; the broker's MQTT
-- worker removes the endpoint - the client's secret from the mosquitto
-- password_file (the web console cannot maintain that file) plus the
-- CLIENTS.AUTH and CLIENTS.STATUS rows - and marks the row DONE. A
-- client-initiated unregister over the bootstrap channel instead
-- deactivates the record (STATUS.CSTATE = 'DEACT') directly in the broker,
-- leaving it in place so the fingerprint cannot be silently re-registered;
-- the console's Deregister can still remove such a deactivated record.
--

CREATE TABLE IF NOT EXISTS `DEREGS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `UID` int(20) NOT NULL,
  `REQUESTED` datetime NOT NULL,
  `STATUS` tinytext NOT NULL DEFAULT 'PENDING',
  `DONE` datetime DEFAULT NULL,
  PRIMARY KEY (`ID`),
  KEY `IDX_DEREGS_STATUS` (`STATUS`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `P2PTOKENS`
--
-- Single-use P2P transfer grants (docs/p2p.md 5, Phase 1). The broker mints
-- one row per deploy target: a new token, the ordered source list (JSON:
-- [{uid, ip, port}], always terminated by the server entry), and a 5-minute
-- expiry. The token rides inside the signed grant envelope embedded in the
-- deploy command; the requester presents it to the first source in the list
-- and may walk the list with the same token. The broker marks the row USED
-- on the terminal report (completion or an exhausted walk) and sweeps
-- expired unused rows.
--

CREATE TABLE IF NOT EXISTS `P2PTOKENS` (
  `TOKEN` char(36) NOT NULL,
  `PKGID` int(20) NOT NULL,
  `REQUID` int(20) NOT NULL,
  `SOURCES` tinytext NOT NULL,
  `EXPIRES` datetime NOT NULL,
  `USED` datetime DEFAULT NULL,
  PRIMARY KEY (`TOKEN`),
  KEY `IDX_P2PTOKENS_EXPIRES` (`EXPIRES`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `P2PTRANSFERS`
--
-- Live P2P transfer progress per (deploy, endpoint, file) (docs/p2p.md 7.5,
-- Phase 1). The broker upserts one row per throttled p2p_progress report
-- (STATE FETCHING/VERIFYING, RECEIVED/TOTAL bytes, the current source); the
-- terminal p2p_fetch_ok / p2p_fetch_fail report sets DONE/FAILED. The
-- console's deploy status view polls this table. The broker sweep marks
-- stale in-flight rows TIMEDOUT.
--

CREATE TABLE IF NOT EXISTS `P2PTRANSFERS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `AID` char(36) NOT NULL,
  `UID` int(20) NOT NULL,
  `FILEID` int(20) NOT NULL,
  `STATE` tinytext NOT NULL,
  `RECEIVED` bigint(20) NOT NULL DEFAULT 0,
  `TOTAL` bigint(20) NOT NULL DEFAULT 0,
  `SRCUID` int(20) DEFAULT NULL,
  `ERR` tinytext DEFAULT NULL,
  `TS` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UQ_P2PTRANSFERS` (`AID`,`UID`,`FILEID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `QUERYRESULTS`
--
-- Sensor results from a client's answer to a query command (protocol 6.1,
-- 7.3). One row per results entry: a successful sensor (STATUS 'OK', OUTPUT
-- set) or a per-sensor failure (STATUS 'ERR', ERR set). QID is the query
-- command's QID, which the client echoes in data.qid (the outbox QID, the
-- envelope id, and data.qid are the same value). Filled in by the broker's
-- MQTT worker.
--

CREATE TABLE IF NOT EXISTS `QUERYRESULTS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `CMDID` int(20) NOT NULL,
  `QID` char(36) NOT NULL,
  `UID` int(20) NOT NULL,
  `SENSORID` int(20) NOT NULL,
  `STATUS` tinytext NOT NULL,
  `OUTPUT` mediumtext DEFAULT NULL,
  `ERR` tinytext DEFAULT NULL,
  `TS` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  KEY `IDX_QUERYRESULTS_QID` (`QID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `QUERYNOMATCH`
--
-- Endpoints that reported no match for a conditional query (protocol 7.3):
-- the query's condition tree evaluated false on the endpoint, so it
-- published a NO_MATCH answer (data.qid echoed, no results) instead of
-- sensor results. One row per (QID, UID) - the unique key is the QoS 1
-- redelivery dedup. The console's query clock stops when every online
-- endpoint in the target has a row here or in QUERYRESULTS (the command
-- deadline remains the bound for endpoints that never respond at all).
-- Filled in by the broker's MQTT worker.
--

CREATE TABLE IF NOT EXISTS `QUERYNOMATCH` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `CMDID` int(20) NOT NULL,
  `QID` char(36) NOT NULL,
  `UID` int(20) NOT NULL,
  `TS` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UQ_QUERYNOMATCH` (`QID`,`UID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Current Database: `LOGS`
--

CREATE DATABASE IF NOT EXISTS `LOGS` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE `LOGS`;

--
-- Table structure for table `AUTH`
--

CREATE TABLE IF NOT EXISTS `AUTH` (
  `ID` int(20) NOT NULL,
  `DATE` datetime NOT NULL,
  `TYPE` tinytext NOT NULL,
  `MESSAGE` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Table structure for table `SYSTEM`
--

CREATE TABLE IF NOT EXISTS `SYSTEM` (
  `ID` int(20) NOT NULL,
  `DATE` datetime NOT NULL,
  `TYPE` tinytext NOT NULL,
  `MESSAGE` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
