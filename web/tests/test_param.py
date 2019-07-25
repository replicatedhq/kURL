from install_scripts import param


def test_param_env(mocker):
    mocker.patch('install_scripts.param.param_cache', {})
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()

    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE'})
    val = param.lookup('TEST_KEY', '/test/key', default='DEFAULT VALUE')
    assert val == 'TEST VALUE'

    # there is no param cache with env
    mocker.patch.dict('os.environ', {'TEST_KEY': 'TEST VALUE 2'})
    val = param.lookup('TEST_KEY', '/test/key', default='DEFAULT VALUE')
    assert val == 'TEST VALUE 2'

    # test default
    val = param.lookup('TEST_KEY_NOTFOUND', '/test/key/notfound', default='DEFAULT VALUE')
    assert val == 'DEFAULT VALUE'


def test_dict_init(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict init with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    ssm_val = param.param_cache['ssm']
    assert ssm_val is None

    m_map = param.param_cache['m']
    assert m_map == {}


def test_ssm_dict_init(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict init with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    ssm_val = param.param_cache['ssm']
    assert ssm_val is not None

    m_map = param.param_cache['m']
    assert m_map == {}


def test_dict_get(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict_get with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.param_cache['m']['/ssm/name'] = 'test_value'

    val = param.dict_get('/ssm/name')
    assert val == 'test_value'


def test_ssm_dict_get(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict_get with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    param.param_cache['m']['/ssm/name'] = 'test_value'

    val = param.dict_get('/ssm/name')
    assert val == 'test_value'


def test_dict_set(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict_set with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.dict_set('/ssm/name', 'test_value')

    val_get = param.dict_get('/ssm/name')
    assert val_get == 'test_value'


def test_ssm_dict_set(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test dict_set with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    param.dict_set('/ssm/name', 'test_value')

    val_get = param.dict_get('/ssm/name')
    assert val_get == 'test_value'


def test_default(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test default with env
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': ''})

    param.init()
    param.dict_set('/ssm/name', 'test_value')

    # since USE_EC2_PARAMETERS is NOT set, the param cache is NOT utilized
    # i.e., the DEFAULT value will be returned by lookup
    val = param.lookup('SSM_NAME', '/ssm/name', default='default_value')
    assert val == 'default_value'


def test_ssm_default(mocker):
    mocker.patch('install_scripts.param.param_cache', {})

    # test default with ssm
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()

    # when ssm_get_parameter returns an empty dict, the value returned from the function
    # should be the default value of SSM_NAME
    mocker.patch('install_scripts.param.ssm_get_parameter', return_value={'Parameter': {}})
    val = param.lookup('SSM_NAME', '/ssm/name', default='default_value')
    assert val == 'default_value'


def test_ssm_param_cache_hit(mocker):
    mocker.patch('install_scripts.param.param_cache', {})
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    param.dict_set('/ssm/name', 'test_value')

    # we should expect a cache hit here, i.e. we should NOT expect an exception triggered by an api call without creds
    val = param.lookup('SSM_NAME', '/ssm/name', default='default_value')
    assert val == 'test_value'


def test_ssm_param_cache_miss(mocker):
    mocker.patch('install_scripts.param.param_cache', {})
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    param.dict_set('/ssm/name', 'ssm_val')

    # an ssm cache miss should trigger an api call, and then a cache write
    mocker.patch('install_scripts.param.ssm_get_parameter', return_value={
        'Parameter': {
            'Name': '/ssm/name/two',
            'Value': 'ssm_val_two'
        }
    })
    param.lookup('SSM_NAME_NOT_FOUND', '/ssm/name/two', default='default_value')

    should_be_cached = param.dict_get('/ssm/name/two')
    assert should_be_cached == 'ssm_val_two'


def test_ssm_param_cache_miss_then_hit(mocker):
    mocker.patch('install_scripts.param.param_cache', {})
    mocker.patch.dict('os.environ', {'USE_EC2_PARAMETERS': '1'})

    param.init()
    param.dict_set('/ssm/name', 'ssm_val')

    # an ssm cache miss should trigger an api call which will in turn cache the ssm_name : ssm_val pair
    mocker.patch('install_scripts.param.ssm_get_parameter', return_value={
        'Parameter': {
            'Name': 'ssm/name/two',
            'Value': 'ssm_val_two'
        }
    })
    param.lookup('CACHED_SSM_NAME', '/ssm/name/two', default='default_value')

    # should NOT need mocker here for an api call because the ssm_name : ssm_val pair should have been cached
    cached_val = param.lookup('CACHED_SSM_NAME', '/ssm/name/two', default='default_value')
    assert cached_val == 'ssm_val_two'
