// This procedure.dsl was generated automatically
// === procedure_autogen starts ===
procedure 'Whoami', description: '', {

    step 'Whoami', {
        description = ''
        command = new File(pluginDir, "dsl/procedures/Whoami/steps/Whoami.pl").text
        shell = 'ec-perl'

        postProcessor = '''$[/myProject/perl/postpLoader]'''
    }
// === procedure_autogen ends, checksum: 371fa7caca9866cb7ac2a0983c3ecd4f ===
// Do not update the code above the line
// procedure properties declaration can be placed in here, like
// property 'property name', value: "value"
}