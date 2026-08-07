# Pester 3.x (Windows-bundled 3.4.0) unit tests for the offline/pure helpers in
# scripts\_jrs_common.ps1. NO live server is contacted -- only Get-GotchaHint,
# Resolve-JrsConfig (env-var path) and Assert-JrsOk are exercised.

. "$PSScriptRoot/../scripts/_jrs_common.ps1"

Describe "Get-GotchaHint" {
    It "returns the strict-Jackson hint for UnrecognizedPropertyException" {
        $h = Get-GotchaHint -Code '400' -Body 'com.fasterxml...UnrecognizedPropertyException: foo'
        $h | Should Match 'strict-Jackson'
    }
    It "returns the dashboards hint for resource.in.use" {
        $h = Get-GotchaHint -Code '400' -Body 'error: resource.in.use somewhere'
        $h | Should Match 'dashlet'
    }
    It "returns the SQL hint for JSSecurityException" {
        $h = Get-GotchaHint -Code '400' -Body 'net.sf...JSSecurityException at validateSQL'
        $h | Should Match 'SELECT'
    }
    It "returns empty string for an unmatched body" {
        $h = Get-GotchaHint -Code '200' -Body 'everything is fine'
        $h | Should Be ''
    }
}

Describe "Resolve-JrsConfig env-var precedence" {
    AfterEach {
        Remove-Item Env:JRS_URL  -ErrorAction SilentlyContinue
        Remove-Item Env:JRS_USER -ErrorAction SilentlyContinue
        Remove-Item Env:JRS_PASS -ErrorAction SilentlyContinue
    }

    It "reads ServerUrl/User/Password from env vars and trims a trailing slash" {
        $env:JRS_URL  = 'http://jrs.example:8080/'
        $env:JRS_USER = 'envuser'
        $env:JRS_PASS = 'envpass'
        $cfg = Resolve-JrsConfig
        $cfg.ServerUrl | Should Be 'http://jrs.example:8080'
        $cfg.User      | Should Be 'envuser'
        $cfg.Password  | Should Be 'envpass'
    }

    It "lets the -ServerUrl param override the env var" {
        $env:JRS_URL  = 'http://from-env:8080'
        $env:JRS_USER = 'envuser'
        $env:JRS_PASS = 'envpass'
        $cfg = Resolve-JrsConfig -ServerUrl 'http://from-param:9090'
        $cfg.ServerUrl | Should Be 'http://from-param:9090'
    }
}

Describe "Resolve-JrsConfig named environment profiles" {
    # These tests only run meaningfully when the local (gitignored)
    # jrs.config.json defines an "environments" block; the unknown-name test
    # works either way.
    AfterEach {
        Remove-Item Env:JRS_ENV -ErrorAction SilentlyContinue
        Remove-Item Env:JRS_URL -ErrorAction SilentlyContinue
    }

    It "throws (listing defined names) for an unknown profile" {
        { Resolve-JrsConfig -Env definitely_not_a_real_env } | Should Throw
    }

    It "honors `$env:JRS_ENV and ignores a stale JRS_URL while a profile is active" {
        $cfgPath = "$PSScriptRoot/../jrs.config.json"
        if (-not (Test-Path $cfgPath)) { return }   # config-less machine: skip
        $names = (Get-Content $cfgPath -Raw | ConvertFrom-Json).environments.PSObject.Properties.Name
        if (-not $names) { return }                 # no profiles defined: skip
        $env:JRS_ENV = $names[0]
        $env:JRS_URL = 'http://stale-export:9/x'
        $cfg = Resolve-JrsConfig
        $cfg.ServerUrl | Should Not Be 'http://stale-export:9/x'
        $cfg.Env       | Should Be $names[0]
    }
}

Describe "Assert-JrsOk" {
    It "returns the response on a 2xx code" {
        $r = Assert-JrsOk -Response @{ Code = '200'; Body = 'ok' } -Operation 'x'
        $r.Code | Should Be '200'
        $r.Body | Should Be 'ok'
    }
    It "throws on a non-2xx code" {
        { Assert-JrsOk -Response @{ Code = '404'; Body = 'nope' } -Operation 'x' } | Should Throw
    }
}
