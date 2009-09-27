# Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2007-2009 SvenDowideit@foswiki.com
# All Rights Reserved. 
# Foswiki Contributors are listed in the AUTHORS file in the root of 
# this distribution. NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

package Foswiki::Users::HTTPDUserAdminUser;
use base 'Foswiki::Users::Password';

use HTTPD::UserAdmin ();
use HTTPD::Authen ();
use Assert;
use strict;
use Foswiki::Users::Password;
use Error qw( :try );

=pod

---+ package Foswiki::Users::HTTPDUserAdminUser

Password manager that uses HTTPD::UserAdmin to manage users and passwords.

Subclass of =[[%SCRIPTURL{view}%/%SYSTEMWEB%/PerlDoc?module=Foswiki::Users::Password][Foswiki::Users::Password]]=.
See documentation of that class for descriptions of the methods of this class.

Duplicates functionality of
=[[%SCRIPTURL{view}%/%SYSTEMWEB%/PerlDoc?module=Foswiki::Users::HtPasswdUser][Foswiki::Users::HtPasswdUser]]=;
and Adds the possiblilty of using DBM files, and databases to store the user information.

see http://search.cpan.org/~lds/HTTPD-User-Manage-1.66/lib/HTTPD/UserAdmin.pm

=cut

sub new {
    my( $class, $session ) = @_;

    my $this = $class->SUPER::new( $session );

	my %configuration =  (
			DBType =>					$Foswiki::cfg{HTTPDUserAdminContrib}{DBType} || 'Text',
			Host =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Host} || '',
			Port =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Port} || '',
			DB =>						$Foswiki::cfg{HTTPDUserAdminContrib}{DB} || $Foswiki::cfg{Htpasswd}{FileName},
			#uncommenting User seems to crash when using Text DBType :(
			#User =>						$Foswiki::cfg{HTTPDUserAdminContrib}{User},
			Auth =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Auth} || '',
			Encrypt =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Encrypt} || 'crypt',
			Locking =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Locking} || '',
			Path =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Path} || '',
			Debug =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Debug},
			Flags =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Flags} || '',
			Driver =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Driver} || '',
			Server =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Server},	#undef == go detect
			UserTable =>				$Foswiki::cfg{HTTPDUserAdminContrib}{UserTable} || '',
			NameField =>				$Foswiki::cfg{HTTPDUserAdminContrib}{NameField} || '',
			PasswordField =>			$Foswiki::cfg{HTTPDUserAdminContrib}{PasswordField} || '',
			#Debug =>				1
             );

	$this->{configuration} = \%configuration;

    $this->{userDatabase} = new HTTPD::UserAdmin(%configuration);

#	print STDERR "new HTTPDAuth".join(', ', $this->{userDatabase}->list())."\n" if ($Foswiki::cfg{HTTPDUserAdminContrib}{Debug});

    return $this;
}

#add func to HTTPD::UserAdmin::SQL so i can ask for a list of users by fields..
#else do it the long way
sub listMatchingUsers {
        my($this, $field, $value) = @_;
        my $self = $this->{userDatabase};
        my @list;
        
        if ($Foswiki::cfg{HTTPDUserAdminContrib}{DBType} eq 'SQL') {
	    my $statement = 
		sprintf("SELECT %s from %s WHERE %s = '%s'\n",
			@{$self}{qw(NAMEFIELD USERTABLE)}, $field, $value);
	    print STDERR $statement if $self->debug;
	    my $sth = $self->{'_DBH'}->prepare($statement);
	    Carp::carp("Cannot prepare sth ($DBI::err): $DBI::errstr")
		unless $sth;
	    $sth->execute || Carp::croak($DBI::errstr);
	    my $user;
	    while($user = $sth->fetchrow) {
		push(@list, $user);
	    }
	    $sth->finish;
    } else {
	    my @userlist = $this->{userDatabase}->list();
	    foreach my $user (@userlist) {
		    my $userValue = fetchField($this, $user, $field);
		    push(@list, $user) if (defined($userValue) and ($userValue eq $value));
	    }
    }
    return @list;
}

=begin TML

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    $this->SUPER::finish();
#don't do this - we don't want to write the .htpasswd file every time we open it for reading.
#    $this->{userDatabase}->commit();
    undef $this->{userDatabase};
}

=pod

---++ ObjectMethod readOnly(  ) -> boolean

returns true if the password file is not currently modifyable

=cut

sub readOnly {
    my $this = shift;

    if ($this->{configuration}->{DBType} eq 'SQL') {
    } else {
        #file based
        my $path = $this->{configuration}->{DB};
        if (-e $path && -d $path && !-w $path) {
            #if the file has been set to non-writable
            return 1;
        }      
    }
    #TODO: use the flags...

    $this->{session}->enterContext('passwords_modifyable');
    return 0;
}

sub canFetchUsers {
    return 1;
}
sub fetchUsers {
    my $this = shift;
    my @users = $this->{userDatabase}->list();
    require Foswiki::ListIterator;
    return new Foswiki::ListIterator(\@users);
}

sub fetchPass {
    my( $this, $login ) = @_;
    ASSERT( $login ) if DEBUG;
    
    my $r;
    if ($this->{userDatabase}->exists( $login )) {
	$r = $this->{userDatabase}->password( $login );
	$this->{error} = undef;
    }
    return $r;
}

sub checkPassword {
    my ( $this, $login, $password ) = @_;
	
	#TODO: this should be extracted to a new LoginManager i think
	my $authen = new HTTPD::Authen($this->{configuration});
	return $authen->check($login, $password);
}

sub removeUser {
    my( $this, $login ) = @_;
    ASSERT( $login ) if DEBUG;

    $this->{error} = undef;
    my $r;
    try {
        $r = $this->{userDatabase}->delete( $login );
        #$this->{error} = $this->{apache}->error() unless (defined($r));        
	$this->{userDatabase}->commit();
    } catch Error::Simple with {
        $this->{error} = 'problem deleting user';
    };
    return $r;
}

=pod

---++ ObjectMethod setPassword( $user, $newPassU, $oldPassU ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.

=cut

sub setPassword {
    my( $this, $login, $newPassU, $oldPassU ) = @_;
    ASSERT( $login ) if DEBUG;

    if( defined($oldPassU)) {
        if ($oldPassU != 1) {
            my $ok = 0;
            try {
                $ok = $this->checkPassword( $login, $oldPassU );
            } catch Error::Simple with {
            };
            unless( $ok ) {
                $this->{error} = "Wrong password";
                return 0;
            }
        }
    }

    my $added = 0;
    try {
        if ($this->{userDatabase}->exists( $login) ) {
            #$added = $this->{userDatabase}->update( $login, $newPassU );
	    my $settings = $this->{userDatabase}->fetch($login, ('emails'));
	    $added = $this->{userDatabase}->update($login, $newPassU, $settings);
        } else {
            $added = $this->{userDatabase}->add( $login, $newPassU );
        }
	$this->{userDatabase}->commit();
        $this->{error} = undef;
    } catch Error::Simple with {
        $this->{error} = 'problem changing password';
    };

    return $added;
}

sub error {
    my $this = shift;
    return $this->{error} || undef;
}

sub isManagingEmails {
    return 1;
}

#special accessors for HTTPDUserAdminUserMapping
sub fetchField {
    my( $this, $login, $fieldname) = @_;
	return unless ($this->{userDatabase}->exists($login));
	#my $settings = $this->{userDatabase}->get_fields(-user=>$login);
	my $settings = $this->{userDatabase}->fetch($login, ($fieldname));	
	#use Data::Dumper;
	#print STDERR "\nsettings . ".$settings." ..".Dumper($settings, keys(%{$settings}));
	
	return $settings->{$fieldname};
}
sub setField {
    my( $this, $login, $fieldname, $value) = @_;
	return unless ($this->{userDatabase}->exists($login));
    #my $r = $this->{userDatabase}->update($login, undef,  {$fieldname=>$value} );
    	    my $settings = $this->{userDatabase}->fetch($login, ('emails'));
    $settings->{$fieldname} = $value;
    $this->{userDatabase}->update($login, undef, $settings);

    $this->{userDatabase}->commit();
	return $value;
}

# emails are stored in extra info field as a ; separated list
sub getEmails {
    my( $this, $login) = @_;
	return unless ($this->{userDatabase}->exists($login));
	my $setting = fetchField($this, $login, 'emails') || '';
	
    my @r = split(/;/, $setting);
    $this->{error} = undef;
    return @r;
}
sub setEmails {
    my $this = shift;
    my $login = shift;
    my $r = setField($this, $login, 'emails', join(';', @_) );
    $this->{error} =  undef;
    return $r;
}
sub findUserByEmail {
    my( $this, $email ) = @_;
    ASSERT($email) if DEBUG;
    
    return $this->listMatchingUsers('emails', $email);
}

1;
