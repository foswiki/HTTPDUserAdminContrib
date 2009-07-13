# ---+ Extensions
# ---++ HTTPDUserAdminContrib
#more feature rich password handleing, using HTTPD::UserAdmin - supports Text, DBM and SQL backends

# **SELECT Text,DBM,SQL**
#DBType - The type of database, one of 'DBM', 'Text', or 'SQL' (Default is 'Text')
$Foswiki::cfg{HTTPDUserAdminContrib}{DBType} = "Text";

# **STRING 200**
#DB - The database name (Default is '.htpasswd' for DBM & Text databases)
$Foswiki::cfg{HTTPDUserAdminContrib}{DB} = $Foswiki::cfg{Htpasswd}{FileName};

# **STRING 30**
#Server - HTTP server name (Default is the generic class, that works with NCSA, Apache and possibly others)
#Note: run 'perl t/support.t matrix' to see what support is currently available
$Foswiki::cfg{HTTPDUserAdminContrib}{Server} = "apache";

# **SELECT crypt,MD5,none**
#Encrypt - One of 'crypt', 'MD5', or 'none' (no encryption. Defaults to 'crypt'
$Foswiki::cfg{HTTPDUserAdminContrib}{Encrypt} = "crypt";

# **BOOLEAN**
#Locking - Boolean, Lock Text and DBM files (Default is true)
$Foswiki::cfg{HTTPDUserAdminContrib}{Locking} = "true";

# **PATH**
#Path - Relative DB files are resolved to this value (Default is '.')
$Foswiki::cfg{HTTPDUserAdminContrib}{Path} = ".";

# **BOOLEAN**
#Debug - Boolean, Turn on debug mode
$Foswiki::cfg{HTTPDUserAdminContrib}{Debug} = "";

# **SELECT rwc,rw,r,w**
#Flags - The read, write and create flags. There are four modes: rwc - the default, open for reading, writing and creating. rw - open for reading and writing. r - open for reading only. w - open for writing only.
$Foswiki::cfg{HTTPDUserAdminContrib}{Flags} = "rwc";

# ---+++ Specific to DBM files:
# **STRING 30**
#DBMF - The DBM file implementation to use (Default is 'NDBM')
$Foswiki::cfg{HTTPDUserAdminContrib}{DBMF} = "NDBM";
# **STRING 30**
#Mode - The file creation mode, defaults to '0644'
$Foswiki::cfg{HTTPDUserAdminContrib}{Mode} = "0644";

# ---+++ Specific to DBI
# We talk to an SQL server via Tim Bunce's DBI interface. For more info see: http://www.hermetica.com/technologia/DBI/
# **STRING 30**
#Host - Server hostname
$Foswiki::cfg{HTTPDUserAdminContrib}{Host} = "";
# **STRING 30**
#Port - Server port
$Foswiki::cfg{HTTPDUserAdminContrib}{Port} = "";
# **STRING 30**
#User - Database login name
$Foswiki::cfg{HTTPDUserAdminContrib}{User} = "";
# **PASSWORD**
#Auth - Database login password
$Foswiki::cfg{HTTPDUserAdminContrib}{Auth} = "";
# **STRING 30**
#Driver - Driver for DBI (Default is 'mSQL')
$Foswiki::cfg{HTTPDUserAdminContrib}{Driver} = "mSQL";
# **STRING 30**
#UserTable - Table with field names below (set ={HTTPDUserAdminContrib}{DB}= for the Database Schema name)
$Foswiki::cfg{HTTPDUserAdminContrib}{UserTable} = "";
# **STRING 30**
#NameField - Field for the name (Default is 'user')
$Foswiki::cfg{HTTPDUserAdminContrib}{NameField} = "user";
# **STRING 30**
#NameField - Field for the wikiname (only used if {Register}{AllowLoginName} is on) (Default is 'wikiname')
$Foswiki::cfg{HTTPDUserAdminContrib}{WikiNameField} = "wikiname";
# **STRING 30**
#PasswordField - Field for the password (Default is 'password')
$Foswiki::cfg{HTTPDUserAdminContrib}{PasswordField} = "password";
# **STRING 30**
#GroupTable - Table with field names below (set ={HTTPDUserAdminContrib}{DB}= for the Database Schema name)
# only applicable if UserMapping is set to Foswiki::Users::HTTPDUserAdminUserMapping
$Foswiki::cfg{HTTPDUserAdminContrib}{GroupTable} = "";
# **STRING 30**
#GroupNameField - Field for the group (Default is 'group')
$Foswiki::cfg{HTTPDUserAdminContrib}{GroupNameField} = "group";
# **STRING 30**
#userNameField - Field for the name (Default is 'user') (must match the User table's NameField in value)
$Foswiki::cfg{HTTPDUserAdminContrib}{UserNameField} = "user";

