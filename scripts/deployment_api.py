#!/usr/bin/env python3
"""
Deployment API for multi-branch management
Provides REST API endpoints for the dashboard to manage deployments
"""

import os
import json
import subprocess
import configparser
from flask import Flask, jsonify, request
from flask_cors import CORS
import docker
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
CLIENT_DIR = os.path.join(ROOT_DIR, 'clients')
DEPLOYMENTS_DIR = os.path.join(ROOT_DIR, 'deployments')
SCRIPT_PATH = os.path.join(SCRIPT_DIR, 'manage_multi_branch_deployment.sh')

# Docker client
docker_client = docker.from_env()

def run_deployment_script(client_name, action, branch_name=None, extra_args=None):
    """Run the deployment script and return the result"""
    cmd = [SCRIPT_PATH, client_name, action]
    if branch_name:
        cmd.append(branch_name)
    if extra_args:
        cmd.extend(extra_args)
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Command timed out after 5 minutes',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': str(e),
            'returncode': -1
        }

def get_deployment_info(client_name, branch_name):
    """Get deployment information from .deployment_info file"""
    deployment_name = f"{client_name}-{branch_name}"
    deployment_dir = os.path.join(DEPLOYMENTS_DIR, deployment_name)
    info_file = os.path.join(deployment_dir, '.deployment_info')
    
    if not os.path.exists(info_file):
        return None
    
    info = {}
    try:
        with open(info_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    info[key] = value
    except Exception as e:
        logger.error(f"Error reading deployment info: {e}")
        return None
    
    return info

def get_container_status(deployment_name):
    """Get Docker container status"""
    container_name = f"odoo-{deployment_name}"
    
    try:
        container = docker_client.containers.get(container_name)
        return {
            'status': container.status,
            'health': container.attrs.get('State', {}).get('Health', {}).get('Status', 'unknown'),
            'created': container.attrs.get('Created'),
            'started': container.attrs.get('State', {}).get('StartedAt'),
            'ports': container.attrs.get('NetworkSettings', {}).get('Ports', {}),
            'image': container.attrs.get('Config', {}).get('Image', ''),
            'labels': container.attrs.get('Config', {}).get('Labels', {})
        }
    except docker.errors.NotFound:
        return {'status': 'not_found'}
    except Exception as e:
        logger.error(f"Error getting container status: {e}")
        return {'status': 'error', 'error': str(e)}

@app.route('/api/clients', methods=['GET'])
def list_clients():
    """List all clients"""
    try:
        clients = []
        if os.path.exists(CLIENT_DIR):
            for client_name in os.listdir(CLIENT_DIR):
                client_path = os.path.join(CLIENT_DIR, client_name)
                if os.path.isdir(client_path):
                    # Get branches
                    branches = []
                    try:
                        result = subprocess.run(['git', 'branch'], 
                                              cwd=client_path, 
                                              capture_output=True, 
                                              text=True)
                        if result.returncode == 0:
                            for line in result.stdout.split('\n'):
                                line = line.strip()
                                if line:
                                    current = line.startswith('*')
                                    branch_name = line.lstrip('* ').strip()
                                    if branch_name:
                                        branches.append({
                                            'name': branch_name,
                                            'current': current
                                        })
                    except Exception as e:
                        logger.error(f"Error getting branches for {client_name}: {e}")
                    
                    # Get branch-version mappings
                    mappings = {}
                    config_file = os.path.join(client_path, '.odoo_branch_config')
                    if os.path.exists(config_file):
                        try:
                            with open(config_file, 'r') as f:
                                for line in f:
                                    if '=' in line:
                                        branch, version = line.strip().split('=', 1)
                                        mappings[branch] = version
                        except Exception as e:
                            logger.error(f"Error reading branch config for {client_name}: {e}")
                    
                    clients.append({
                        'name': client_name,
                        'branches': branches,
                        'version_mappings': mappings
                    })
        
        return jsonify({'clients': clients})
    except Exception as e:
        logger.error(f"Error listing clients: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments', methods=['GET'])
def list_deployments(client_name):
    """List deployments for a client"""
    try:
        deployments = []
        
        # Find all deployments for this client
        if os.path.exists(DEPLOYMENTS_DIR):
            for deployment_name in os.listdir(DEPLOYMENTS_DIR):
                if deployment_name.startswith(f"{client_name}-"):
                    branch_name = deployment_name[len(client_name)+1:]
                    deployment_dir = os.path.join(DEPLOYMENTS_DIR, deployment_name)
                    
                    if os.path.isdir(deployment_dir):
                        # Get deployment info
                        info = get_deployment_info(client_name, branch_name)
                        if info:
                            # Get container status
                            container_status = get_container_status(deployment_name)
                            
                            deployments.append({
                                'branch': branch_name,
                                'deployment_name': deployment_name,
                                'odoo_version': info.get('ODOO_VERSION', 'unknown'),
                                'port': int(info.get('PORT', 0)),
                                'postgres_port': int(info.get('POSTGRES_PORT', 0)),
                                'url': info.get('URL', ''),
                                'traefik_url': info.get('TRAEFIK_URL', ''),
                                'created': info.get('CREATED', ''),
                                'status': container_status
                            })
        
        return jsonify({'deployments': deployments})
    except Exception as e:
        logger.error(f"Error listing deployments for {client_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>', methods=['GET'])
def get_deployment(client_name, branch_name):
    """Get specific deployment information"""
    try:
        deployment_name = f"{client_name}-{branch_name}"
        info = get_deployment_info(client_name, branch_name)
        
        if not info:
            return jsonify({'error': 'Deployment not found'}), 404
        
        # Get container status
        container_status = get_container_status(deployment_name)
        
        # Get recent logs
        logs = []
        try:
            cmd = ['docker', 'logs', '--tail', '50', f'odoo-{deployment_name}']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                logs = result.stdout.split('\n')[-50:]  # Last 50 lines
        except Exception as e:
            logger.error(f"Error getting logs: {e}")
        
        return jsonify({
            'branch': branch_name,
            'deployment_name': deployment_name,
            'odoo_version': info.get('ODOO_VERSION', 'unknown'),
            'port': int(info.get('PORT', 0)),
            'postgres_port': int(info.get('POSTGRES_PORT', 0)),
            'url': info.get('URL', ''),
            'traefik_url': info.get('TRAEFIK_URL', ''),
            'created': info.get('CREATED', ''),
            'status': container_status,
            'logs': logs
        })
    except Exception as e:
        logger.error(f"Error getting deployment {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/deploy', methods=['POST'])
def deploy_branch(client_name, branch_name):
    """Deploy a branch"""
    try:
        data = request.get_json() or {}
        port = data.get('port')
        
        extra_args = []
        if port:
            extra_args.extend(['--port', str(port)])
        
        result = run_deployment_script(client_name, 'deploy', branch_name, extra_args)
        
        if result['success']:
            return jsonify({'message': 'Deployment started successfully'})
        else:
            return jsonify({'error': result['stderr'] or result['stdout']}), 500
    except Exception as e:
        logger.error(f"Error deploying {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/start', methods=['POST'])
def start_deployment(client_name, branch_name):
    """Start a deployment"""
    try:
        result = run_deployment_script(client_name, 'start', branch_name)
        
        if result['success']:
            return jsonify({'message': 'Deployment started successfully'})
        else:
            return jsonify({'error': result['stderr'] or result['stdout']}), 500
    except Exception as e:
        logger.error(f"Error starting deployment {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/stop', methods=['POST'])
def stop_deployment(client_name, branch_name):
    """Stop a deployment"""
    try:
        result = run_deployment_script(client_name, 'stop', branch_name)
        
        if result['success']:
            return jsonify({'message': 'Deployment stopped successfully'})
        else:
            return jsonify({'error': result['stderr'] or result['stdout']}), 500
    except Exception as e:
        logger.error(f"Error stopping deployment {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/restart', methods=['POST'])
def restart_deployment(client_name, branch_name):
    """Restart a deployment"""
    try:
        result = run_deployment_script(client_name, 'restart', branch_name)
        
        if result['success']:
            return jsonify({'message': 'Deployment restarted successfully'})
        else:
            return jsonify({'error': result['stderr'] or result['stdout']}), 500
    except Exception as e:
        logger.error(f"Error restarting deployment {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/remove', methods=['DELETE'])
def remove_deployment(client_name, branch_name):
    """Remove a deployment"""
    try:
        result = run_deployment_script(client_name, 'remove', branch_name, ['--force'])
        
        if result['success']:
            return jsonify({'message': 'Deployment removed successfully'})
        else:
            return jsonify({'error': result['stderr'] or result['stdout']}), 500
    except Exception as e:
        logger.error(f"Error removing deployment {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/clients/<client_name>/deployments/<branch_name>/logs', methods=['GET'])
def get_deployment_logs(client_name, branch_name):
    """Get deployment logs"""
    try:
        deployment_name = f"{client_name}-{branch_name}"
        lines = request.args.get('lines', '100')
        
        cmd = ['docker', 'logs', '--tail', lines, f'odoo-{deployment_name}']
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            logs = result.stdout.split('\n')
            return jsonify({'logs': logs})
        else:
            return jsonify({'error': 'Failed to get logs'}), 500
    except Exception as e:
        logger.error(f"Error getting logs for {client_name}/{branch_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/status', methods=['GET'])
def system_status():
    """Get system status"""
    try:
        # Get Docker info
        docker_info = docker_client.info()
        
        # Get deployments count
        deployments_count = 0
        if os.path.exists(DEPLOYMENTS_DIR):
            deployments_count = len([d for d in os.listdir(DEPLOYMENTS_DIR) 
                                   if os.path.isdir(os.path.join(DEPLOYMENTS_DIR, d))])
        
        # Get running containers count
        running_containers = len([c for c in docker_client.containers.list() 
                                if c.name.startswith('odoo-')])
        
        return jsonify({
            'docker_version': docker_info.get('ServerVersion', 'unknown'),
            'deployments_count': deployments_count,
            'running_containers': running_containers,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting system status: {e}")
        return jsonify({'error': str(e)}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting Deployment API on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug)