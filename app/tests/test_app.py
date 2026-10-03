import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

os.environ.setdefault('APP_NAME', 'cloudlaunch-api')
os.environ.setdefault('APP_VERSION', '1.0.0')
os.environ.setdefault('FAIL_READY', 'false')
os.environ.setdefault('FAIL_STARTUP', 'false')

from main import app


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as c:
        yield c


def test_index(client):
    rv = client.get('/')
    assert rv.status_code == 200
    data = rv.get_json()
    assert data['service'] == 'cloudlaunch-api'
    assert 'version' in data
    assert 'pod' in data
    assert 'uptime_seconds' in data


def test_health(client):
    rv = client.get('/health')
    assert rv.status_code == 200
    data = rv.get_json()
    assert data['status'] == 'healthy'


def test_ready(client):
    rv = client.get('/ready')
    assert rv.status_code == 200
    data = rv.get_json()
    assert data['status'] == 'ready'


def test_metrics(client):
    rv = client.get('/metrics')
    assert rv.status_code == 200
    assert b'cloudlaunch_http_requests_total' in rv.data


def test_items(client):
    rv = client.get('/api/v1/items')
    assert rv.status_code == 200
    data = rv.get_json()
    assert 'items' in data
    assert len(data['items']) > 0


def test_ready_fail_mode(client):
    os.environ['FAIL_READY'] = 'true'
    import main as m
    m.FAIL_READY = True
    rv = client.get('/ready')
    assert rv.status_code == 503
    data = rv.get_json()
    assert data['status'] == 'not_ready'
    m.FAIL_READY = False
    os.environ['FAIL_READY'] = 'false'
