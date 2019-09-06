package FlowPlugin::CBOAuth2Centrify;
use strict;
use warnings;
use base qw/FlowPDF/;
use FlowPDF::Log;
use Data::Dumper;
use URI;
use MIME::Base64;
use ElectricCommander;
use JSON;
use HTTP::Request::Common;

# Feel free to use new libraries here, e.g. use File::Temp;

# Service function that is being used to set some metadata for a plugin.
sub pluginInfo {
    return {
        pluginName          => '@PLUGIN_KEY@',
        pluginVersion       => '@PLUGIN_VERSION@',
        configFields        => ['config'],
        configLocations     => ['ec_plugin_cfgs'],
        defaultConfigValues => {}
    };
}

# Auto-generated method for the procedure Setup Oauth2 Configuration/Initiate Redirect
# Add your code into this method and it will be called when step runs
sub initiateRedirect {
    my ($self, $runtimeParameters) = @_;

    my $state = {
        jobId => $ENV{COMMANDER_JOBID}
    };

    my $base64_state = encode_base64(encode_json($state));
    my $uri = URI->new($runtimeParameters->{tenant} . "/oauth2/authorize/$runtimeParameters->{app}");

    $uri->query_form(
        response_type => 'code',
        redirect_uri => $self->_generateRedirectUrl($runtimeParameters),
        client_id => $runtimeParameters->{user},
        state => $base64_state,
        scope => $runtimeParameters->{scope},
    );

    logInfo("Redirect URI: $uri");
    my $ec = ElectricCommander->new;
    $ec->setProperty({propertyName => '/myJob/report-urls/Redirect URI', value => $uri});
}


# Auto-generated method for the procedure Setup Oauth2 Configuration/Wait for the Code
# Add your code into this method and it will be called when step runs
sub waitForTheCode {
    my ($pluginObject, $runtimeParameters, $stepResult) = @_;

    my $ec = ElectricCommander->new;
    my $code = '';
    while(!$code) {
        logInfo("Waiting for the auth code...");
        sleep(2);
        eval { $code = $ec->getPropertyValue('/myJob/cb_auth_code') };
        logInfo("Code: $code");
    }
}


# Auto-generated method for the procedure Setup Oauth2 Configuration/Finalize Configuration
# Add your code into this method and it will be called when step runs
sub finalizeConfiguration {
    my ($self, $runtimeParameters, $stepResult) = @_;

    my $context = $self->getContext;

    my $ec = ElectricCommander->new;
    my $auth_code = $ec->getPropertyValue('/myJob/cb_auth_code');

    logInfo("Got Auth code: $auth_code");

    my $client_id = $runtimeParameters->{user};
    my $client_secret = $runtimeParameters->{password};
    my $tenant = $runtimeParameters->{tenant};
    my $app = $runtimeParameters->{app};

    my $ua = LWP::UserAgent->new;

    my $redirect_uri = $self->_generateRedirectUrl($runtimeParameters);
    my $grant_type = 'authorization_code';

    my $url = $tenant . '/oauth2/token/' . $app;

    my $formvars = [
      redirect_uri => $redirect_uri,
      grant_type => $grant_type,
      code => $auth_code,
      client_id => $client_id,
      client_secret => $client_secret,
    ];

    logDebug("URL: $url");
    logDebug($formvars);

    my $response = $ua->request(POST $url, $formvars);

    unless ($response->is_success) {
        bailOut("Failed to exchange authorization code for the pair of tokens");
    }

    logInfo("Exchanged the auth code for the pair of tokens");

    my $json = decode_json($response->content);
    my $access_token = $json->{access_token};
    my $refresh_token = $json->{refresh_token};

    unless($refresh_token) {
        bailOut("Failed to get refresh token. Please ensure that your OAuth2 Provider issues refresh tokens.");
    }

    # Saving config
    my $configName = $runtimeParameters->{configName};

    logInfo("Saving tokens into the configuration");

    my $jobId = $ec->runProcedure({
        procedureName => 'CreateConfiguration',
        projectName => '@PLUGIN_NAME@',
        actualParameter => [
        {
            actualParameterName => 'config',
            value => $configName,
        },
        {
            actualParameterName => 'tenant',
            value => $runtimeParameters->{tenant},
        },
        {
            actualParameterName => 'appId',
            value => $runtimeParameters->{app},
        },
        {
            actualParameterName => 'clientFlow',
            value => 'auth_code_flow',
        },
        {
            actualParameterName => 'credential',
            value => $configName,
        },
        {
            actualParameterName => 'tokens_credential',
            value => $configName . '_tokens',
        },
        ],
        credential => [
            {
                credentialName => $configName,
                userName => $runtimeParameters->{user},
                password => $runtimeParameters->{password},
            },
            {
                credentialName => $configName . '_tokens',
                userName => '',
                password => $refresh_token,
            },
        ]
    })->findvalue('//jobId');

    logInfo("Configuration job ID: $jobId");

    $ec->setProperty({
        propertyName => '/myJob/report-urls/Config Job',
        value => "/commander/link/jobDetails/jobs/$jobId"
    });

    my $status = $ec->getJobStatus({jobId => $jobId})->findvalue('//status');
    while($status ne 'completed') {
        $status = $ec->getJobStatus({jobId => $jobId})->findvalue('//status');
        sleep(2);
        logInfo("Waiting for the configuration to complete, status $status...");
    }
}

# Auto-generated method for the procedure Whoami/Whoami
# Add your code into this method and it will be called when step runs
sub whoami {
    my ($pluginObject, $r, $stepResult) = @_;

    my $url = $r->{tenant} . '/oauth2/token/' . $r->{appId};

    my $formvars = [
      grant_type => 'refresh_token',
      client_id => $r->{user},
      client_secret => $r->{password},
      refresh_token => $r->{tokens_password}
    ];

    my $ua = LWP::UserAgent->new;

    my $response = $ua->request(POST $url, $formvars);

    unless($response->is_success) {
        die "Failed to refresh the token";
    }

    my $json = decode_json($response->content);
    my $access_token = $json->{access_token};

    my $request = HTTP::Request->new(GET => $r->{tenant} . '/security/whoami');
    $request->header('Authorization', "Bearer $access_token");
    $response = $ua->request($request);
    print Dumper $response;

    my $json = decode_json($response->content);
    print Dumper $json;
}


## === step ends ===
# Please do not remove the marker above, it is used to place new procedures into this file.



sub _generateRedirectUrl {
    my ($self, $r) = @_;

    my $hostname = $r->{flowServerHostname} || '$[/server/hostName]';
    return 'https://' . $hostname . '/commander/pages/@PLUGIN_KEY@/oauth2_redirect_run';
}

1;
