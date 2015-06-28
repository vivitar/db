module db;

public import db.api;
public import db.core;



version (USE_MYSQL) {
	import db.driver.mysql;
}

version (USE_SQLITE) {
	import db.driver.sqlite;
}

version (USE_POSTGRESQL) {
	import db.driver.postgresql;
}

version (USE_INTERBASE) {
	import db.driver.interbase;
}