/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.11-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: POLICY
-- ------------------------------------------------------
-- Server version	10.11.11-MariaDB-0+deb12u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `POLICY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `POLICY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `POLICY`;

--
-- Dumping events for database 'POLICY'
--

--
-- Dumping routines for database 'POLICY'
--

--
-- Current Database: `DISCOVERY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `DISCOVERY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `DISCOVERY`;

--
-- Table structure for table `CONFIG`
--

DROP TABLE IF EXISTS `CONFIG`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `CONFIG` (
  `ID` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'DISCOVERY'
--

--
-- Dumping routines for database 'DISCOVERY'
--

--
-- Current Database: `CONTENT`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `CONTENT` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `CONTENT`;

--
-- Table structure for table `CATEGORIES`
--

DROP TABLE IF EXISTS `CATEGORIES`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `CATEGORIES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `CSID` int(20) NOT NULL,
  `NAME` tinytext NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `PACKAGES`
--

DROP TABLE IF EXISTS `PACKAGES`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `PACKAGES` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SENSORHISTORY`
--

DROP TABLE IF EXISTS `SENSORHISTORY`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SENSORHISTORY` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SENSORPARAMS`
--

DROP TABLE IF EXISTS `SENSORPARAMS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SENSORPARAMS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `SID` int(20) NOT NULL,
  `FIELD` tinytext NOT NULL,
  `TYPE` tinytext NOT NULL,
  `VALOPTS` tinytext NOT NULL,
  `DEFAULTVAL` tinytext DEFAULT NULL,
  `HELPTEXT` tinytext DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SENSORS`
--

DROP TABLE IF EXISTS `SENSORS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SENSORS` (
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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SETS`
--

DROP TABLE IF EXISTS `SETS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SETS` (
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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'CONTENT'
--

--
-- Dumping routines for database 'CONTENT'
--

--
-- Current Database: `QUERY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `QUERY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `QUERY`;

--
-- Table structure for table `QUESTIONS`
--

DROP TABLE IF EXISTS `QUESTIONS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `QUESTIONS` (
  `ID` int(20) NOT NULL,
  `QUESTION` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'QUERY'
--

--
-- Dumping routines for database 'QUERY'
--

--
-- Current Database: `INTEGRITY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `INTEGRITY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `INTEGRITY`;

--
-- Table structure for table `CONFIG`
--

DROP TABLE IF EXISTS `CONFIG`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `CONFIG` (
  `ID` int(20) NOT NULL,
  `MODE` tinyint(4) NOT NULL,
  `ENABLED` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `IGNORELIST`
--

DROP TABLE IF EXISTS `IGNORELIST`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `IGNORELIST` (
  `ID` int(20) NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `PERMISSIONS`
--

DROP TABLE IF EXISTS `PERMISSIONS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `PERMISSIONS` (
  `UID` tinytext NOT NULL,
  `ACCESS` tinyint(4) NOT NULL DEFAULT 1,
  `MANAGE_MODULE` tinyint(4) NOT NULL DEFAULT 0,
  `MANAGE_CLIENTS` tinyint(4) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `WATCHLIST`
--

DROP TABLE IF EXISTS `WATCHLIST`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `WATCHLIST` (
  `ID` int(20) NOT NULL,
  `OS` tinytext NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `WATCH_DEFAULT`
--

DROP TABLE IF EXISTS `WATCH_DEFAULT`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `WATCH_DEFAULT` (
  `OS` tinytext NOT NULL,
  `PATH` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'INTEGRITY'
--

--
-- Dumping routines for database 'INTEGRITY'
--

--
-- Current Database: `SUMMARY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `SUMMARY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `SUMMARY`;

--
-- Dumping events for database 'SUMMARY'
--

--
-- Dumping routines for database 'SUMMARY'
--

--
-- Current Database: `INVENTORY`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `INVENTORY` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `INVENTORY`;

--
-- Dumping events for database 'INVENTORY'
--

--
-- Dumping routines for database 'INVENTORY'
--

--
-- Current Database: `AUTH`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `AUTH` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `AUTH`;

--
-- Table structure for table `2FA`
--

DROP TABLE IF EXISTS `2FA`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `2FA` (
  `UID` int(20) NOT NULL,
  `METHOD` tinytext NOT NULL,
  `AUTHDATA` tinytext NOT NULL,
  `ENABLED` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `GROUPS`
--

DROP TABLE IF EXISTS `GROUPS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `GROUPS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `AUTHOR` int(20) DEFAULT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SESSION`
--

DROP TABLE IF EXISTS `SESSION`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SESSION` (
  `ID` int(20) NOT NULL,
  `SID` tinytext NOT NULL,
  `START` timestamp NOT NULL,
  `EXPIRES` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `USERPREFS`
--

DROP TABLE IF EXISTS `USERPREFS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `USERPREFS` (
  `ID` int(20) NOT NULL,
  `PREFKEY` tinytext NOT NULL,
  `PREFVAL` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `USERS`
--

DROP TABLE IF EXISTS `USERS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `USERS` (
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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'AUTH'
--

--
-- Dumping routines for database 'AUTH'
--

--
-- Current Database: `SYSTEM`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `SYSTEM` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `SYSTEM`;

--
-- Table structure for table `CONFIG`
--

DROP TABLE IF EXISTS `CONFIG`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `CONFIG` (
  `CKEY` tinytext NOT NULL,
  `CVAL` tinytext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `CPUHIST`
--

DROP TABLE IF EXISTS `CPUHIST`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `CPUHIST` (
  `TIMESTAMP` datetime DEFAULT NULL,
  `PCT` tinytext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'SYSTEM'
--

--
-- Dumping routines for database 'SYSTEM'
--

--
-- Current Database: `CLIENTS`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `CLIENTS` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `CLIENTS`;

--
-- Table structure for table `AUTH`
--

DROP TABLE IF EXISTS `AUTH`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `AUTH` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `FINGERPRINT` tinytext NOT NULL,
  `PUBKEY` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `GROUPS`
--

DROP TABLE IF EXISTS `GROUPS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `GROUPS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `NAME` tinytext NOT NULL,
  `AUTHOR` int(20) DEFAULT NULL,
  `CREATED` datetime NOT NULL,
  `MODIFIED` datetime DEFAULT NULL,
  `EDITOR` int(20) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `STATUS`
--

DROP TABLE IF EXISTS `STATUS`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `STATUS` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'CLIENTS'
--

--
-- Dumping routines for database 'CLIENTS'
--

--
-- Current Database: `LOGS`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `LOGS` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `LOGS`;

--
-- Table structure for table `AUTH`
--

DROP TABLE IF EXISTS `AUTH`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `AUTH` (
  `ID` int(20) NOT NULL,
  `DATE` datetime NOT NULL,
  `TYPE` tinytext NOT NULL,
  `MESSAGE` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SYSTEM`
--

DROP TABLE IF EXISTS `SYSTEM`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `SYSTEM` (
  `ID` int(20) NOT NULL,
  `DATE` datetime NOT NULL,
  `TYPE` tinytext NOT NULL,
  `MESSAGE` text NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'LOGS'
--

--
-- Dumping routines for database 'LOGS'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-11-03 16:28:46
