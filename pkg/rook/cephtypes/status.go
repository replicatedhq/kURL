package cephtypes

// lint:file-ignore ST1003 this file is generated

type CephStatus struct {
	Fsid   string `json:"fsid"`
	Health struct {
		Checks map[string]struct {
			Severity string `json:"severity"`
			Summary  struct {
				Message string `json:"message"`
			} `json:"summary"`
		} `json:"checks"`
		Status string `json:"status"`
	} `json:"health"`
	ElectionEpoch int      `json:"election_epoch"`
	Quorum        []int    `json:"quorum"`
	QuorumNames   []string `json:"quorum_names"`
	QuorumAge     int      `json:"quorum_age"`
	Monmap        struct {
		Epoch             int    `json:"epoch"`
		Fsid              string `json:"fsid"`
		Modified          string `json:"modified"`
		Created           string `json:"created"`
		MinMonRelease     int    `json:"min_mon_release"`
		MinMonReleaseName string `json:"min_mon_release_name"`
		Features          struct {
			Persistent []string      `json:"persistent"`
			Optional   []interface{} `json:"optional"`
		} `json:"features"`
		Mons []struct {
			Rank        int    `json:"rank"`
			Name        string `json:"name"`
			PublicAddrs struct {
				Addrvec []struct {
					Type  string `json:"type"`
					Addr  string `json:"addr"`
					Nonce int    `json:"nonce"`
				} `json:"addrvec"`
			} `json:"public_addrs"`
			Addr       string `json:"addr"`
			PublicAddr string `json:"public_addr"`
		} `json:"mons"`
	} `json:"monmap"`
	Osdmap struct {
		Osdmap struct {
			Epoch          int  `json:"epoch"`
			NumOsds        int  `json:"num_osds"`
			NumUpOsds      int  `json:"num_up_osds"`
			NumInOsds      int  `json:"num_in_osds"`
			Full           bool `json:"full"`
			Nearfull       bool `json:"nearfull"`
			NumRemappedPgs int  `json:"num_remapped_pgs"`
		} `json:"osdmap"`
	} `json:"osdmap"`
	Pgmap struct {
		PgsByState []struct {
			StateName string `json:"state_name"`
			Count     int    `json:"count"`
		} `json:"pgs_by_state"`
		NumPgs                  int     `json:"num_pgs"`
		NumPools                int     `json:"num_pools"`
		NumObjects              int     `json:"num_objects"`
		DataBytes               int64   `json:"data_bytes"`
		BytesUsed               int64   `json:"bytes_used"`
		BytesAvail              int64   `json:"bytes_avail"`
		BytesTotal              int64   `json:"bytes_total"`
		InactivePgsRatio        float64 `json:"inactive_pgs_ratio"`
		DegradedObjects         int     `json:"degraded_objects"`
		DegradedTotal           int     `json:"degraded_total"`
		DegradedRatio           float64 `json:"degraded_ratio"`
		MisplacedObjects        int     `json:"misplaced_objects"`
		MisplacedTotal          int     `json:"misplaced_total"`
		MisplacedRatio          float64 `json:"misplaced_ratio"`
		RecoveringObjectsPerSec int     `json:"recovering_objects_per_sec"`
		RecoveringBytesPerSec   int     `json:"recovering_bytes_per_sec"`
		RecoveringKeysPerSec    int     `json:"recovering_keys_per_sec"`
		NumObjectsRecovered     int     `json:"num_objects_recovered"`
		NumBytesRecovered       int     `json:"num_bytes_recovered"`
		NumKeysRecovered        int     `json:"num_keys_recovered"`
		ReadBytesSec            int     `json:"read_bytes_sec"`
		WriteBytesSec           int     `json:"write_bytes_sec"`
		ReadOpPerSec            int     `json:"read_op_per_sec"`
		WriteOpPerSec           int     `json:"write_op_per_sec"`
	} `json:"pgmap"`
	Fsmap struct {
		Epoch     int           `json:"epoch"`
		ByRank    []interface{} `json:"by_rank"`
		UpStandby int           `json:"up:standby"`
	} `json:"fsmap"`
	Mgrmap struct {
		Epoch       int    `json:"epoch"`
		ActiveGid   int    `json:"active_gid"`
		ActiveName  string `json:"active_name"`
		ActiveAddrs struct {
			Addrvec []struct {
				Type  string `json:"type"`
				Addr  string `json:"addr"`
				Nonce int    `json:"nonce"`
			} `json:"addrvec"`
		} `json:"active_addrs"`
		ActiveAddr       string        `json:"active_addr"`
		ActiveChange     string        `json:"active_change"`
		Available        bool          `json:"available"`
		Standbys         []interface{} `json:"standbys"`
		Modules          []string      `json:"modules"`
		AvailableModules []struct {
			Name          string `json:"name"`
			CanRun        bool   `json:"can_run"`
			ErrorString   string `json:"error_string"`
			ModuleOptions map[string]struct {
				Name         string        `json:"name"`
				Type         string        `json:"type"`
				Level        string        `json:"level"`
				Flags        int           `json:"flags"`
				DefaultValue string        `json:"default_value"`
				Min          string        `json:"min"`
				Max          string        `json:"max"`
				EnumAllowed  []interface{} `json:"enum_allowed"`
				Desc         string        `json:"desc"`
				LongDesc     string        `json:"long_desc"`
				Tags         []interface{} `json:"tags"`
				SeeAlso      []interface{} `json:"see_also"`
			} `json:"module_options"`
		} `json:"available_modules"`
		Services struct {
			Dashboard  string `json:"dashboard"`
			Prometheus string `json:"prometheus"`
		} `json:"services"`
		AlwaysOnModules struct {
			Nautilus []string `json:"nautilus"`
		} `json:"always_on_modules"`
	} `json:"mgrmap"`
	Servicemap struct {
		Epoch    int    `json:"epoch"`
		Modified string `json:"modified"`
		Services struct {
			Rgw struct {
				Daemons struct {
					Summary        string `json:"summary"`
					RookCephStoreA struct {
						StartEpoch int    `json:"start_epoch"`
						StartStamp string `json:"start_stamp"`
						Gid        int    `json:"gid"`
						Addr       string `json:"addr"`
						Metadata   struct {
							Arch              string `json:"arch"`
							CephRelease       string `json:"ceph_release"`
							CephVersion       string `json:"ceph_version"`
							CephVersionShort  string `json:"ceph_version_short"`
							ContainerHostname string `json:"container_hostname"`
							ContainerImage    string `json:"container_image"`
							Cpu               string `json:"cpu"`
							Distro            string `json:"distro"`
							DistroDescription string `json:"distro_description"`
							DistroVersion     string `json:"distro_version"`
							FrontendConfig0   string `json:"frontend_config#0"`
							FrontendType0     string `json:"frontend_type#0"`
							Hostname          string `json:"hostname"`
							KernelDescription string `json:"kernel_description"`
							KernelVersion     string `json:"kernel_version"`
							MemSwapKb         string `json:"mem_swap_kb"`
							MemTotalKb        string `json:"mem_total_kb"`
							NumHandles        string `json:"num_handles"`
							Os                string `json:"os"`
							Pid               string `json:"pid"`
							PodName           string `json:"pod_name"`
							PodNamespace      string `json:"pod_namespace"`
							ZoneId            string `json:"zone_id"`
							ZoneName          string `json:"zone_name"`
							ZonegroupId       string `json:"zonegroup_id"`
							ZonegroupName     string `json:"zonegroup_name"`
						} `json:"metadata"`
					} `json:"rook.ceph.store.a"`
				} `json:"daemons"`
			} `json:"rgw"`
		} `json:"services"`
	} `json:"servicemap"`
	ProgressEvents map[string]struct {
		Message  string  `json:"message"`
		Progress float64 `json:"progress"`
	} `json:"progress_events"`
}
