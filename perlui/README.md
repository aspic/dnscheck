DNSCheck perl-frontend
======================
An experimental (and a bit more minimalistic) perl front-end for the
DNSChecker. In its current state it supports both mysql and postgresql
as the database back end (this is dependent on what back end DNSCheck
initially runs on).

Dependencies
------------
The front end depend of a small set of modules:

* CGI
* CGI::Session
* DBI
* Template
* YAML::Tiny
* File::Slurp
* Digest::SHA
* Net::DNS
* JSON
* Data::Validate::Domain
