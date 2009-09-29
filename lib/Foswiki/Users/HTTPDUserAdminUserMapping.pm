# Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2007-2009 Sven Dowideit, SvenDowideit@fosiki.com
# and Foswiki Contributors. All Rights Reserved. Foswiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

=begin TML

---+ package Foswiki::Users::HTTPDUserAdminUserMapping

over-rides TopicUserMapping to store Groups outside topics.
 
=cut

package Foswiki::Users::HTTPDUserAdminUserMapping;
use Foswiki::Users::TopicUserMapping;
use Foswiki::Func;
use base 'Foswiki::Users::TopicUserMapping';

use strict;
use Assert;
use Error qw( :try );

use HTTPD::GroupAdmin;

#use Monitor;
#Monitor::MonitorMethod('Foswiki::Users::HTTPDUserAdminUserMapping');

=begin TML

---++ ClassMethod new ($session, $impl)

Constructs a new user mapping handler of this type, referring to $session
for any required foswiki services.

=cut

sub new {
    my( $class, $session ) = @_;

    my $this = $class->SUPER::new( $session, '' );
    
	my %configuration =  (
			DBType =>					$Foswiki::cfg{HTTPDUserAdminContrib}{DBType} || 'Text',
			Host =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Host} || '',
			Port =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Port} || '',
			DB =>						$Foswiki::cfg{HTTPDUserAdminContrib}{DB} || $Foswiki::cfg{Htpasswd}{FileName},
			#uncommenting User seems to crash when using Text DBType :(
			#User =>					$Foswiki::cfg{HTTPDUserAdminContrib}{User},
			Auth =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Auth} || '',
			Encrypt =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Encrypt} || 'crypt',
			Locking =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Locking} || '',
    #TODO: need to test the LOCKING - it seems to fail on my trunk, and when it does, give a server error
			Path =>						$Foswiki::cfg{HTTPDUserAdminContrib}{Path} || '',
			Debug =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Debug},
			Flags =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Flags} || '',
			Driver =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Driver} || '',
			Server =>					$Foswiki::cfg{HTTPDUserAdminContrib}{Server},	#undef == go detect
			GroupTable =>				$Foswiki::cfg{HTTPDUserAdminContrib}{GroupTable} || '',
			NameField =>				$Foswiki::cfg{HTTPDUserAdminContrib}{UserNameField} || '',
			GroupField =>			    $Foswiki::cfg{HTTPDUserAdminContrib}{GroupNameField} || '',
			#Debug =>				1
             );

	$this->{configuration} = \%configuration;
	my %groupCfg = %configuration;
	if (defined($Foswiki::cfg{HTTPDUserAdminContrib}{GroupDB}) 
            and $Foswiki::cfg{HTTPDUserAdminContrib}{GroupDB} ne '') {
            $groupCfg{DB} = $Foswiki::cfg{HTTPDUserAdminContrib}{GroupDB};
            $this->{groupDatabase} = new HTTPD::GroupAdmin(%groupCfg);
        }
        
    my $implPasswordManager = $Foswiki::cfg{PasswordManager};
    $implPasswordManager = 'Foswiki::Users::Password'
      if( $implPasswordManager eq 'none' );
    eval "require $implPasswordManager";
    die $@ if $@;
    $this->{passwords} = $implPasswordManager->new( $session );
    
    #TODO: need to assert that the pwd manager has the required methods - fetchField...
    
    #if password manager says sorry, we're read only today
    #'none' is a special case, as it means we're not actually using the password manager for
    # registration.
    if ($this->{passwords}->readOnly() && ($Foswiki::cfg{PasswordManager} ne 'none')) {
        $session->writeWarning( 'TopicUserMapping has TURNED OFF EnableNewUserRegistration, because the password file is read only.' );
        $Foswiki::cfg{Register}{EnableNewUserRegistration} = 0;
    }
    
    Foswiki::registerTagHandler( 'USERLIST', \&USERLIST );

    return $this;
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
    if (defined($this->{groupDatabase})) {
        $this->{groupDatabase}->commit();
        undef $this->{groupDatabase};
    }
}


=begin TML

---++ ObjectMethod supportsRegistration () -> false
return 1 if the UserMapper supports registration (ie can create new users)

=cut

sub supportsRegistration {
    return 1;
}

=begin TML

---++ ObjectMethod handlesUser ( $cUID, $login, $wikiname) -> $boolean

Called by the Foswiki::Users object to determine which loaded mapping
to use for a given user (must be fast).

=cut

sub handlesUser {
    my ($this, $cUID, $login, $wikiname) = @_;

    if (defined $cUID && !length($this->{mapping_id})) {
        # TopicUserMapping is special - for backwards compatibility, it assumes
        # responsibility for _all_ non BaseMapping users
        # if you're needing to mix the TopicUserMapping with others, 
        # define $this->{mapping_id} = 'TopicUserMapping_';
        return 1;
    } else {
        # Used when (if) TopicUserMapping is subclassed
        return 1 if ( defined $cUID && $cUID =~ /^($this->{mapping_id})/ );
    }

    return 1 if ($login && $this->getLoginName( $login ));
    return 0;
}


=begin TML

---++ ObjectMethod getCanonicalUserID ($login, $dontcheck) -> cUID

Convert a login name to the corresponding canonical user name. The
canonical name can be any string of 7-bit alphanumeric and underscore
characters, and must correspond 1:1 to the login name.
(undef on failure)

(if dontcheck is true, return a cUID for a nonexistant user too - used for registration)

=cut

sub getCanonicalUserID {
    my( $this, $login, $dontcheck ) = @_;
#    print STDERR "\nTopicUserMapping::getCanonicalUserID($login, ".($dontcheck||'undef').")";

    unless ($dontcheck) {
        return unless (_userReallyExists($this, $login));
    }

    $login = Foswiki::Users::mapLogin2cUID($login);
    $login = $this->{mapping_id}.$login;
#print STDERR " OK ($login)";
    return $login;
}

=begin TML

---++ ObjectMethod getLoginName ($cUID) -> login

converts an internal cUID to that user's login
(undef on failure)

=cut

sub getLoginName {
    my( $this, $user ) = @_;
    ASSERT($user) if DEBUG;

    #can't call userExists - its recursive
    #return unless (userExists($this, $user));

    # Remove the mapping id in case this is a subclass
    $user =~ s/$this->{mapping_id}// if $this->{mapping_id};

    use bytes;
    # use bytes to ignore character encoding
    $user =~ s/_(\d\d)/chr($1)/ge;
    no bytes;

    return unless (_userReallyExists($this, $user));
    
    return $user;
}

=begin TML

---++ ObjectMethod _userReallyExists ($login) -> boolean

test if the login is in the WikiUsers topic, or in the password file
depending on the AllowLoginNames setting

=cut

sub _userReallyExists {
    my( $this, $login ) = @_;
    
    my $pass = $this->{passwords}->fetchPass( $login );
    return unless (defined($pass));
    return if ("$pass" eq "0"); #login invalid... (TODO: what does that really mean)
    return 1;
}

=begin TML

---++ ObjectMethod removeUser( $user ) -> $boolean

Delete the users entry. Removes the user from the password
manager and user mapping manager. Does *not* remove their personal
topics, which may still be linked.

=cut

sub removeUser {
    my( $this, $user ) = @_;
    $this->ASSERT_IS_CANONICAL_USER_ID($user) if DEBUG;
    my $ln = $this->getLoginName( $user );
    $this->{passwords}->removeUser($ln);
}


=begin TML

---++ ObjectMethod getWikiName ($cUID) -> wikiname

Map a canonical user name to a wikiname. If it fails to find a WikiName, it will
attempt to find a matching loginname, and use an escaped version of that.
If there is no matching WikiName or LoginName, it returns undef.

=cut

sub getWikiName {
    my ($this, $cUID) = @_;
    ASSERT($cUID) if DEBUG;
    ASSERT($cUID =~ /^$this->{mapping_id}/) if DEBUG;

    my $wikiname;
    if( $Foswiki::cfg{Register}{AllowLoginName} ) {
	    $wikiname = $this->{passwords}->fetchField($cUID, $Foswiki::cfg{HTTPDUserAdminContrib}{WikiNameField});
    } else {
        # If the mapping isn't enabled there's no point in loading it
    }

    unless ($wikiname) {
        #sanitise the generated WikiName - fix up email addresses and stuff
        $wikiname = getLoginName( $this, $cUID );
        if ($wikiname) {
            $wikiname =~ s/$Foswiki::cfg{NameFilter}//go;
            $wikiname =~ s/\.//go;
        }
    }

    #print STDERR "--------------------------------------cUID : $cUID => $wikiname\n";
    return $wikiname;
 
}

=begin TML

---++ ObjectMethod userExists($cUID) -> $boolean

Determine if the user already exists or not. Whether a user exists
or not is determined by the password manager.

=cut

sub userExists {
    my( $this, $cUID ) = @_;
    ASSERT($cUID) if DEBUG;
    $this->ASSERT_IS_CANONICAL_USER_ID($cUID) if DEBUG;

    # Do this to avoid a password manager lookup
    return 1 if $cUID eq $this->{session}->{user};

    my $loginName = $this->getLoginName( $cUID );
    return unless (defined($loginName) && ($loginName ne ''));

    if( $loginName eq $Foswiki::cfg{DefaultUserLogin} ) {
        return $loginName;
    }

    if( $this->isGroup( $loginName )) {
        return $loginName;
    }

    # Look them up in the password manager (can be slow).
    if( $this->{passwords}->canFetchUsers() &&
       $this->{passwords}->fetchPass( $loginName )) {
        return $loginName;
    }

    return undef;
}

=begin TML

---++ ObjectMethod eachUser () -> listIterator of cUIDs

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub eachUser {
    my( $this ) = @_;

    return $this->{passwords}->fetchUsers();
}

=begin TML

---++ ObjectMethod findUserByEmail( $email ) -> \@users
   * =$email= - email address to look up
Return a list of canonical user names for the users that have this email
registered with the password manager or the user mapping manager.

The password manager is asked first for whether it maps emails.
If it doesn't, then the user mapping manager is asked instead.

=cut

sub findUserByEmail {
    my( $this, $email ) = @_;
    ASSERT($email) if DEBUG;

    return $this->{passwords}->findUserByEmail($email);
}

=begin TML

---++ ObjectMethod getEmails($user) -> @emailAddress

If this is a user, return their email addresses. If it is a group,
return the addresses of everyone in the group.

The password manager and user mapping manager are both consulted for emails
for each user (where they are actually found is implementation defined).

Duplicates are removed from the list.

=cut

sub getEmails {
    my( $this, $user, $seen ) = @_;
    $this->ASSERT_IS_CANONICAL_USER_ID($user) if DEBUG;

    $seen ||= {};

    my %emails = ();

    if ($seen->{$user}) {
      #print STDERR "preventing infinit recursion in getEmails($user)\n";
    } else {
      $seen->{$user} = 1;

      if ( $this->isGroup($user) ) {
          my $it = $this->eachGroupMember( $user );
          while( $it->hasNext() ) {
              foreach ($this->getEmails( $it->next(), $seen )) {
                  $emails{$_} = 1;
              }
          }
      } else {
          # get emails from the password manager
          foreach ($this->{passwords}->getEmails( $this->getLoginName( $user ), $seen )) {
              $emails{$_} = 1;
          }
      }
    }

    return keys %emails;
}

=begin TML

---++ ObjectMethod setEmails($user, @emails) -> boolean

Set the email address(es) for the given user.
The password manager is tried first, and if it doesn't want to know the
user mapping manager is tried.

=cut

sub setEmails {
    my $this = shift;
    my $user = shift;
    $this->ASSERT_IS_CANONICAL_USER_ID($user) if DEBUG;

    $this->{passwords}->setEmails( $this->getLoginName( $user ), @_ );
}

=begin TML

---++ ObjectMethod findUserByWikiName ($wikiname) -> list of cUIDs associated with that wikiname

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details. The $skipExistanceCheck parameter
is private to this module, and blocks the standard existence check
to avoid reading .htpasswd when checking group memberships).

=cut

sub findUserByWikiName {
    my( $this, $wn, $skipExistanceCheck ) = @_;
    my @users = ();

    if( $this->isGroup( $wn )) {
        push( @users, $wn);
    } elsif( $Foswiki::cfg{Register}{AllowLoginName} ) {
        # Add additional mappings defined in WikiUsers
        
        my @usernames = $this->{passwords}->listMatchingUsers($Foswiki::cfg{HTTPDUserAdminContrib}{WikiNameField}, $wn);
        push( @users, @usernames );
        
        # Bloody compatibility!
        # The wikiname is always a registered user for the purposes of this
        # mapping. We have to do this because foswiki defines access controls
        # in terms of mapped users, and if a wikiname is *missing* from the
        # mapping there is "no such user".
#HUH?        push( @users, getCanonicalUserID( $this, $wn ));
    } else {
        # The wikiname is also the login name, so we can just convert
        # it directly to a cUID
        my $cUID = getCanonicalUserID( $this, $wn );
        if( $skipExistanceCheck || ($cUID && $this->userExists( $cUID )) ) {
            push( @users, getCanonicalUserID( $this, $wn ));
        }
    }
    return \@users;
}

=begin TML

---++ ObjectMethod checkPassword( $userName, $passwordU ) -> $boolean

Finds if the password is valid for the given user.

Returns 1 on success, undef on failure.

=cut

sub checkPassword {
    my( $this, $userName, $pw ) = @_;
    $this->ASSERT_IS_USER_LOGIN_ID($userName) if DEBUG;
    return $this->{passwords}->checkPassword( $userName, $pw );
}

=begin TML

---++ ObjectMethod setPassword( $user, $newPassU, $oldPassU ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.

=cut

sub setPassword {
    my( $this, $user, $newPassU, $oldPassU ) = @_;
    $this->ASSERT_IS_CANONICAL_USER_ID($user) if DEBUG;
    return $this->{passwords}->setPassword(
        $this->getLoginName( $user ), $newPassU, $oldPassU);
}

=begin TML

---++ ObjectMethod passwordError( ) -> $string

returns a string indicating the error that happened in the password handlers
TODO: these delayed error's should be replaced with Exceptions.

returns undef if no error

=cut

sub passwordError {
    my( $this ) = @_;
    return $this->{passwords}->error();
}




#######################################################################
# don't create or use the MAIN.WikiUsers topic 
# this is a copy of the functionality in TopicUserMapping, with the WikiUser topic part removed
#TODO: shame that its the UI::Registration code that creates the User topic - tahts close to pointless too

sub addUser {
    my ( $this, $login, $wikiname, $password, $emails ) = @_;

    ASSERT($login) if DEBUG;

    # SMELL: really ought to be smarter about this e.g. make a wikiword
    $wikiname ||= $login;

    if( $this->{passwords}->fetchPass( $login )) {
        # They exist; their password must match
        unless( $this->{passwords}->checkPassword( $login, $password )) {
            throw Error::Simple(
                'New password did not match existing password for this user');
        }
        # User exists, and the password was good.
    } else {
        # add a new user

        unless( defined( $password )) {
            require Foswiki::Users;
            $password = Foswiki::Users::randomPassword();
        }

        unless( $this->{passwords}->setPassword( $login, $password )) {
            #print STDERR "\n Failed to add user:  ".$this->{passwords}->error();
            throw Error::Simple(
                'Failed to add user: '.$this->{passwords}->error());
        }
        
        if( !$Foswiki::cfg{Register}{AllowLoginName} ) {
            $wikiname = $login;
        }
        $this->{passwords}->setField($login, $Foswiki::cfg{HTTPDUserAdminContrib}{WikiNameField}, $wikiname);
    }

    my $user = getCanonicalUserID( $this, $login, 1 );
    ASSERT($user) if DEBUG;

    #can't call setEmails here - user may be in the process of being registered
    #TODO; when registration is moved into the mapping, setEmails will happend after the createUserTOpic
    #$this->setEmails( $user, $emails );

    return $user;
}



#######################################################################
# Groups functionality

=begin TML

---++ ObjectMethod eachGroupMember ($group) ->  listIterator of cUIDs

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub eachGroupMember {
    my $this = shift;
    my $group = shift;
    
    return $this->SUPER::eachGroupMember($group) unless (defined($this->{groupDatabase}));
    
    my @users = $this->{groupDatabase}->list($group);
    my @cuids;
    foreach my $ident (@users) {
        if ($this->isGroup($ident)) {
            my $it = $this->eachGroupMember($ident);
            while ( $it->hasNext() ) {
                push( @cuids, $it->next() );
            }
        } else {
            #explicitly convert to cUIDs
            my $cuid = $this->getCanonicalUserID($ident);	#login
		if (defined($cuid)) {
	            push(@cuids, $cuid);
			#print STDERR "pushing $cuid ($ident) onto groupmembers for $group\n";
		} else {
			my $users = $this->findUserByWikiName($ident);
			foreach my $ident (@$users) {
		            push(@cuids, $ident );
				#print STDERR "pushing $ident onto groupmembers for $group\n";
			}
		}
        }
    }
    
    require Foswiki::ListIterator;
    return new Foswiki::ListIterator(\@cuids);
}



=begin TML

---++ ObjectMethod isGroup ($user) -> boolean
TODO: what is $user - wikiname, UID ??
Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub isGroup {
    my ($this, $user) = @_;

    return $this->SUPER::isGroup($user) unless (defined($this->{groupDatabase}));

    # Groups have the same username as wikiname as canonical name
    return 1 if $user eq $Foswiki::cfg{SuperAdminGroup};

    return $this->{groupDatabase}->exists($user);
}

=begin TML

---++ ObjectMethod eachGroup () -> ListIterator of groupnames

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub eachGroup {
    my ( $this ) = @_;
    
    return $this->SUPER::eachGroup() unless (defined($this->{groupDatabase}));

    my @groups = $this->{groupDatabase}->list();

    require Foswiki::ListIterator;
    return new Foswiki::ListIterator( \@groups );
}


=begin TML

---++ ObjectMethod eachMembership ($cUID) -> ListIterator of groups this user is in

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub eachMembership {
    my ($this, $user) = @_;
    
    return $this->SUPER::eachMembership($user) unless (defined($this->{groupDatabase}));

    my $it = $this->eachGroup();
    $it->{filter} = sub {
        #print STDERR "----- is $user in the $_[0] group?";
        $this->isInGroup($user, $_[0]);
    };
    return $it;
}

=begin TML

---++ ObjectMethod isAdmin( $user ) -> $boolean

True if the user is an admin
   * is $Foswiki::cfg{SuperAdminGroup}
   * is a member of the $Foswiki::cfg{SuperAdminGroup}

=cut

sub DONTNEEDTHIS_isAdmin {
    my( $this, $user ) = @_;
    my $isAdmin = 0;
    $this->ASSERT_IS_CANONICAL_USER_ID($user) if DEBUG;

    #TODO: this might not apply now that we have BaseUserMapping - test
    if ($user eq $Foswiki::cfg{SuperAdminGroup}) {
        $isAdmin = 1;
    } else {
        my $sag = $Foswiki::cfg{SuperAdminGroup};
        $isAdmin = $this->isInGroup( $user, $sag );
    }

    return $isAdmin;
}


=begin TML

---++ ObjectMethod isInGroup ($user, $group, $scanning) -> bool

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

=cut

sub isInGroup {
    my( $this, $user, $group, $scanning ) = @_;
    ASSERT($user) if DEBUG;
    
    return $this->SUPER::isInGroup($user, $group, $scanning) unless (defined($this->{groupDatabase}));
    
    return 1 if ($this->{groupDatabase}->exists($group, $user));
    my $wikiname = $this->getWikiName($user);
    return 1 if (defined($wikiname) and ($this->{groupDatabase}->exists($group, $wikiname )));
    
    #now for nested groups :/
    my $it = $this->eachGroupMember($group);
    while ( $it->hasNext() ) {
        return 1 if ($user eq $it->next());
    }
}

sub USERLIST {
    my($session, $params, $aTopic, $aWeb) = @_;  
    
    return '%RED%USERLIST only evaluated for Admin Users%ENDCOLOR%' unless (Foswiki::Func::isAnAdmin());

    require Digest::MD5;
    my $string_id = join(':', map { $_.'="'.$params->{$_}.'"' } keys(%$params));
    my $paging_ID = 'USERINFO'.Digest::MD5::md5_hex($string_id);
    
    my $this = $session->{users};
    my $format = $params->{format} || $params->{_DEFAULT} || '   * $wikiname - $username - ';
    my $pagesize = $params->{pagesize} ||10;
    my $showpage = $session->{request}->param($paging_ID) || $params->{showpage} || 1;
    my $header = $params->{header} || '';
    my $footer = $params->{footer} || '';
    my $separator = $params->{separator} || '$n';
    #exclude these wikinames... 
    my @exclusions = split(/\s*,\s*/, $params->{exclude} || '');
    
    my $it = $this->eachUser();
    my @results;
    my $idx = 0;
    my $startidx = ($showpage-1)*$pagesize;
    my $stopidx = ($showpage)*$pagesize;
    my ($nextidx, $previousidx); #undefined means no nav's needed
    while ($it->hasNext()) {
        my $cuid = $it->next();
        
        my $wikiname = $this->getWikiName($cuid);
        next if (@exclusions ~~ $wikiname);                     #TODO: eeeeek perl 5.10ism
        if ($idx >= $startidx) {
            if ($idx >= $stopidx) {
                $nextidx = $idx; #there is a next element that isn't excluded.
                last;
            }
            my $login = $this->getLoginName($cuid);
            #my $result = '%USERINFO{"'.$login.'" format="'.$format.'"}%';
            my $result = $session->USERINFO({
                                                                _DEFAULT => $login,
                                                                format => $format
                                                                    });
            push(@results, $result);
        }  else {
            $previousidx = $idx; #there is a non-excluded previous element
        }
        $idx++;
    }
    my $result = $header.join($separator, @results).$footer;
    
    my $previouspage = '';
    my $previouspageurl = '';
    if (defined($previousidx)) {
        #TODO: need to rebuild the URL from the incoming, and 'modify/set' the paging_ID's value..
        $previouspageurl = Foswiki::Func::getScriptUrl($aWeb, $aTopic, 'view', $paging_ID => ($showpage-1));
        $previouspage = "[[$previouspageurl][<]]";
    }
    my $nextpage = '';
    my $nextpageurl = '';
    if (defined($nextidx)) {
        #TODO: need to rebuild the URL from the incoming, and 'modify/set' the paging_ID's value..
        $nextpageurl = Foswiki::Func::getScriptUrl($aWeb, $aTopic, 'view', $paging_ID => ($showpage+1));
        $nextpage = "[[$nextpageurl][>]]";
    }
    
    $result =~ s/\$pagenumber/$showpage/ge;
    $result =~ s/\$previouspagenumber/($showpage-1)/ge;
    $result =~ s/\$nextpagenumber/($showpage+1)/ge;

    $result =~ s/\$previouspageurl/$previouspageurl/ge;
    $result =~ s/\$nextpageurl/$nextpageurl/ge;
    
    $result =~ s/\$previouspage/$previouspage/ge;
    $result =~ s/\$nextpage/$nextpage/ge;
    
    $result =~ s/\$sep/$separator/ge;

    $result = Foswiki::expandStandardEscapes($result);
   
    return $result;
}


1;
