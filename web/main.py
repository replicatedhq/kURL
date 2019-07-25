import os

from install_scripts import param
from install_scripts.app import app

param.init()

if __name__ == '__main__':
    app.run(debug=(os.getenv('ENVIRONMENT') == 'dev'),
            host='0.0.0.0', port=5001, threaded=True)
