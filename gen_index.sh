#!/bin/bash

[ -f pkg/index.db ] && rm pkg/index.db
[ -f pkg/index.csv ] && rm pkg/index.csv

sqlite3 pkg/index.db <<EOF
create table packages (
	name              varchar(100) primary key,
	version           varchar(20) not null,
	description       text,
	home_url          varchar(400),
	archive_file_name varchar(100),
	acrhive_sha256    varchar(64)
);

create table depends (
	package_name varchar(100) not null,
	depends_on varchar(100) not null,

	unique (package_name, depends_on),
	foreign key (package_name) references packages (name)
	foreign key (depends_on) references packages (name)
);
EOF

get_field() {
	grep -e "$2\b" $1 | cut -d= -f2- | awk '{$1=$1;print}'
}

sql_quote() {
	val=$(echo "$*" | sed "s/'/''/")
	echo "'$val'"
}

for f in pkg/*.PKGINFO; do
	base=$(basename $f .PKGINFO)
	pkgfile=${base}.pkg.tar.gz
	parts=(${barepkgname//-/ })

	pkgname=$(get_field $f pkgname)
	pkgver=$(get_field $f pkgver)

	echo -n "Adding $pkgname $pkgver"

	pkgdesc=$(get_field $f pkgdesc)
	pkgurl=$(get_field $f url)
	sha256=$(sha256sum pkg/$pkgfile | cut -d" " -f1)
	echo -n "."

	sqlite3 pkg/index.db <<-EOF
	insert into packages values(
		$(sql_quote $pkgname),
		$(sql_quote $pkgver),
		$(sql_quote $pkgdesc),
		$(sql_quote $pkgurl),
		$(sql_quote $pkgfile),
		$(sql_quote $sha256)
	)
	EOF
	echo -n "."

	for dep in $(get_field $f depend); do
		sqlite3 pkg/index.db <<-EOF
		insert into depends values (
			$(sql_quote $pkgname),
			$(sql_quote $dep)
		)
		EOF
	done
	echo -n "."

	echo "$pkgname,$pkgver,$pkgfile,$sha256" >> pkg/index.csv
	echo ".done"
done

echo "Done"
