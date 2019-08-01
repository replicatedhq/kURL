package server

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/replicatedhq/kurl/pkg/build"
)

type Server struct {
	builder *build.Builder
	distDir string
}

func New(builder *build.Builder, distDir string) *Server {
	return &Server{
		builder: builder,
		distDir: distDir,
	}
}

func (s *Server) Run(port string) {
	r := gin.Default()

	r.GET("/", s.Install)

	r.GET("/join", s.Join)
	r.GET("/join.sh", s.Join)

	r.Static("/dist", s.distDir)

	r.Run(port)
}

func (s *Server) Install(c *gin.Context) {
	data, err := s.builder.Install()
	if err != nil {
		c.AbortWithError(http.StatusInternalServerError, err)
		return
	}
	c.Data(http.StatusOK, "text/plain", data)
}

func (s *Server) Join(c *gin.Context) {
	data, err := s.builder.Join()
	if err != nil {
		c.AbortWithError(http.StatusInternalServerError, err)
		return
	}
	c.Data(http.StatusOK, "text/plain", data)
}
