import axios from "axios"

export const getNodeLogs=(nodeId)=>{
    return axios({
        method: 'GET',
        url: `${window.env.API_ENDPOINT}/instance/${nodeId}/node-logs`,
    });
}
