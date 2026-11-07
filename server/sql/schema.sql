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
  `WITHPARAMS` tinyint(1) NOT NULL DEFAULT 0,
  `TIMESTAMP` datetime NOT NULL,
  `EDITOR` int(20) NOT NULL
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
-- Table structure for table `CPUHIST`
--

CREATE TABLE IF NOT EXISTS `CPUHIST` (
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
  PRIMARY KEY (`ID`)
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
