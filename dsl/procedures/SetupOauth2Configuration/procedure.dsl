// This procedure.dsl was generated automatically
// === procedure_autogen starts ===
procedure 'Setup Oauth2 Configuration', description: 'This procedure will setup a configuration for oauth2', {

    step 'Initiate Redirect', {
        description = ''
        command = new File(pluginDir, "dsl/procedures/SetupOauth2Configuration/steps/InitiateRedirect.pl").text
        shell = 'ec-perl'

            shell = '''ec-perl'''
        postProcessor = '''$[/myProject/perl/postpLoader]'''
    }

    step 'Wait for the Code', {
        description = ''
        command = new File(pluginDir, "dsl/procedures/SetupOauth2Configuration/steps/WaitfortheCode.pl").text
        shell = 'ec-perl'

            shell = '''ec-perl'''
        postProcessor = '''$[/myProject/perl/postpLoader]'''
    }

    step 'Finalize Configuration', {
        description = ''
        command = new File(pluginDir, "dsl/procedures/SetupOauth2Configuration/steps/FinalizeConfiguration.pl").text
        shell = 'ec-perl'

            shell = '''ec-perl'''
        postProcessor = '''$[/myProject/perl/postpLoader]'''
    }
// === procedure_autogen ends, checksum: 8de4a56af84853343fc121d66d9b751b ===
// Do not update the code above the line
// procedure properties declaration can be placed in here, like
// property 'property name', value: "value"
}