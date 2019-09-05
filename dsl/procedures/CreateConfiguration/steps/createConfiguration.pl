
## === createConfiguration starts ===
#
#  Copyright 2016 Electric Cloud, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

#########################
## createcfg.pl
#########################

use ElectricCommander;
use ElectricCommander::PropDB;
use JSON;
use strict;
use Data::Dumper;

use constant {
    SUCCESS => 0,
    ERROR   => 1,
};

## get an EC object
my $ec = ElectricCommander->new({debug => 0});

my $projName = '$[/myProject/name]';
my $configPropertySheet;
eval {
    $configPropertySheet = $ec->getPropertyValue('/myProject/ec_configPropertySheet');
    1;
} or do {
    $configPropertySheet = 'ec_plugin_cfgs';
};

eval {
    createConfigurationPropertySheet($configPropertySheet);
    1;
} or do {
    my $err = $@;
    error("Failed to create configuration: $err");
    rollback($configPropertySheet, $err);
    $ec->setProperty("/myJob/configError", $err);
    exit 1;
};

my $steps = [];
my $stepsJSON = eval { $ec->getPropertyValue("/projects/$projName/procedures/CreateConfiguration/ec_stepsWithAttachedCredentials") };
if ($stepsJSON) {
    $steps = decode_json($stepsJSON);
}

my $configName = '$[config]';

eval {
    my $opts = getActualParameters();
    info("Configuration options: " . Dumper ($opts));
    for my $param ($ec->getFormalParameters({
        projectName => $projName,
        procedureName => 'CreateConfiguration',
    })->findnodes('//formalParameter')) {
        my $type = $param->findvalue('type') . '';

        if ($type eq 'credential') {
            my $required = $param->findvalue('required') . '';
            my $fieldName = $param->findvalue('formalParameterName') . '';
            my $credentialName = $opts->{$fieldName};

            my $createEmpty = 0;
            if(!$credentialName && !$required) {
                $createEmpty = 1;
                # Need to create empty credential
                $credentialName = $fieldName;
            }
            info("Found credential: $credentialName, required: $required, create empty: $createEmpty");

            eval {
                createAndAttachCredential(
                    $credentialName,
                    $configName,
                    $configPropertySheet,
                    $steps,
                    $createEmpty
                );
                1;
            } or do {
                my $err = $@;
                die $err;
            };
        }
    }
    1;
} or do {
    my $err = $@;
    error("Failed to create configuration: $err");
    info("Rolling back configuration $configName");
    rollback($configPropertySheet, $err);
    $ec->setProperty("/myJob/configError", $err);
    exit 1;
};

sub info {
    my @messages = @_;

    for my $msg (@messages) {
        print "[INFO] $msg\n";
    }
}

sub error {
    my @messages = @_;

    for my $msg (@messages) {
        print "[ERROR] $msg\n";
    }
}

sub createAndAttachCredential {
    my ($credName, $configName, $configPropertySheet, $steps, $createEmpty) = @_;

    my ($clientID, $clientSecret);
    info("Creating a credential $credName, create empty: $createEmpty");
    my $xpath = eval { $ec->getFullCredential($credName) };
    if ($@) {
        if ($createEmpty) {
            $clientID = '';
            $clientSecret = '';
        }
        else {
            die $@;
        }
    }

    unless($createEmpty) {
        $clientID = $xpath->findvalue("//userName");
        info("Username: $clientID");
        $clientSecret = $xpath->findvalue("//password");
        if ($clientSecret) {
            info("Client secret: ******* (provided)");
        }
        else {
            info("Client secret is empty");
        }
    }

    my $projName = '$[/myProject/projectName]';

    my $credObjectName = $credName eq 'credential' ? $configName : "${configName}_${credName}";
    # Create credential
    info("Deleting old credential $credObjectName");
    eval { $ec->deleteCredential($projName, $credObjectName) };
    info("Creating a new credential $credObjectName");
    $xpath = $ec->createCredential($projName, $credObjectName, $clientID, $clientSecret);

    # Give config the credential's real name
    my $configPath = "/projects/$projName/$configPropertySheet/$configName/$credName";
    $xpath = $ec->setProperty($configPath, $credObjectName);

    # Give job launcher full permissions on the credential
    my $user = '$[/myJob/launchedByUser]';

    my $exists = 0;
    eval {
        $exists = $ec->getAclEntry("user", $user,
            {
                projectName => $projName,
                credentialName => $credObjectName
            });
        1;
    } or do {
        $exists = 0;
    };

    info("ACL exists; $exists");
    unless($exists) {
        info("Creating ACL entry for the credential");
        $xpath = $ec->createAclEntry("user", $user,
            {
                projectName                => $projName,
                credentialName             => $credObjectName,
                readPrivilege              => 'allow',
                modifyPrivilege            => 'allow',
                executePrivilege           => 'allow',
                changePermissionsPrivilege => 'allow'
            });
    }

    info("Setting ACL for the credential $credObjectName for the user $user");

    # Attach credential to steps that will need it
    for my $step( @$steps ) {
        info("Attaching credential $credName to procedure " . $step->{procedureName} . " at step " . $step->{stepName});
        my $apath = $ec->attachCredential($projName, $credObjectName,
                                        {procedureName => $step->{procedureName},
                                         stepName => $step->{stepName}});
    }

}

sub rollback {
    my ($configPropertySheet, $error) = @_;

    if ($error !~ /already exists/) {
        my $configName = '$[config]';
        $ec->deleteProperty("/myProject/$configPropertySheet/$configName");
        info("The configuration property sheet $configName has been removed");
        my $credentials = $ec->getCredentials({projectName => $projName});
        for my $cred ($credentials->findnodes('//credential')) {
            my $name = $cred->findvalue('credentialName')->string_value;
            if ($name =~ /^${configName}_/) {
                $ec->deleteCredential({projectName => $projName, credentialName => $name});
                info("Cleaned credential $name");
            }
        }
    }
}

sub getActualParameters {
    my $x       = $ec->getJobDetails($ENV{COMMANDER_JOBID});
    my $nodeset = $x->find('//actualParameter');
    my $opts;

    foreach my $node ($nodeset->get_nodelist) {
        my $parm = $node->findvalue('actualParameterName');
        my $val  = $node->findvalue('value');
        $opts->{$parm} = "$val";
    }
    return $opts;
}

sub createConfigurationPropertySheet {
    my ($configPropertySheet) = @_;

    eval {
        ## load option list from procedure parameters
        my $ec = ElectricCommander->new;
        $ec->abortOnError(0);
        my $x       = $ec->getJobDetails($ENV{COMMANDER_JOBID});
        my $nodeset = $x->find('//actualParameter');
        my $opts = getActualParameters();

        if (!defined $opts->{config} || "$opts->{config}" eq "") {
            die "config parameter must exist and be non-blank\n";
        }

        # check to see if a config with this name already exists before we do anything else
        my $xpath    = $ec->getProperty("/myProject/$configPropertySheet/$opts->{config}");
        my $property = $xpath->findvalue("//response/property/propertyName");

        if (defined $property && "$property" ne "") {
            my $errMsg = "A configuration named '$opts->{config}' already exists.";
            $ec->setProperty("/myJob/configError", $errMsg);
            die $errMsg;
        }

        my $cfg = new ElectricCommander::PropDB($ec, "/myProject/$configPropertySheet");

        # add all the options as properties
        foreach my $key (keys %{$opts}) {
            if ("$key" eq "config") {
                next;
            }
            $cfg->setCol("$opts->{config}", "$key", "$opts->{$key}");
        }
        1;
    } or do {
        my $err = $@;
        $ec->abortOnError(1);
        die $err;
    };
    info("Created configuration property sheet");
}
## === createConfiguration ends, checksum: 0b88aba200b64206cb87d7ee7b640891 ===
# user-defined code can be placed below this line
# Do not edit the code above the line as it will be updated upon plugin upgrade
