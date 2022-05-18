import axios from "axios"

export const getClusterNodes=(instanceId)=>{
    return axios({
        method: 'GET',
        url: `${window.env.API_ENDPOINT}/instance/${instanceId}/cluster-node`,
    });
}

export const getNodeLogs=(nodeId)=>{
    return axios({
        method: 'GET',
        url: `${window.env.API_ENDPOINT}/instance/${nodeId}/node-logs`,
    });
}
