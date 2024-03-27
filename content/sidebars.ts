import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tkeSidebar: [
    {
      type: "doc",
      id: "README",
      customProps: {
        slug: "/"
      }
    },
    {
      type: 'category',
      label: '网络指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/networking'
      },
      items: [
        'networking/ingress-nginx',
        'networking/clb-to-pod-directly',
        'networking/how-to-use-eip',
        'networking/install-localdns-with-ipvs',
        'networking/expose-grpc-with-tcm',
      ],
    },
    {
      type: 'category',
      label: '存储指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/storage'
      },
      items: [
        'storage/cbs-pvc-expansion',
        'storage/readonlymany-pv',
        'storage/mount-cfs-with-v3',
      ],
    },
    {
      type: 'category',
      label: '监控告警',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/monitoring'
      },
      items: [
        'monitoring/prometheus-scrape-config',
        'monitoring/grafana-dashboard-for-supernode-pod',
      ],
    },
    {
      type: 'category',
      label: '镜像与仓库',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/images'
      },
      items: [
        'images/use-mirror-in-container',
        'images/use-foreign-container-image',
      ],
    },
    {
      type: 'category',
      label: '故障排查',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/troubleshooting'
      },
      items: [
        'troubleshooting/public-service-or-ingress-connect-failed',
      ],
    },
    {
      type: 'category',
      label: '常见应用安装与部署',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/install-apps'
      },
      items: [
        'install-apps/install-harbor-on-tke',
        'install-apps/install-gitlab-on-tke',
        'install-apps/install-kubesphere-on-tke',
      ],
    },
    {
      type: 'category',
      label: '常见问题',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/faq'
      },
      items: [
        'faq/modify-rp-filter-causing-exception',
        'faq/clb-loopback',
        'faq/controller-manager-and-scheduler-unhealthy',
      ],
    },
    {
      type: 'category',
      label: '解决方案',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/solution'
      },
      items: [
        'solution/multi-account',
        'solution/upgrade-inplace',
      ],
    },
    {
      type: 'category',
      label: '常用 YAML',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/yaml'
      },
      items: [
        'yaml/service',
        'yaml/ingress',
        'yaml/workload',
      ],
    },
    {
      type: 'category',
      label: '附录',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/appendix'
      },
      items: [
        'appendix/useful-kubectl-for-tencent-cloud',
        'appendix/eks-annotations',
        'appendix/ingress-error-code',
        {
          type: 'category',
          label: 'Serverless 集群与超级节点',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/appendix/serverless'
          },
          items: [
            'appendix/serverless/precautions',
            'appendix/serverless/why-tke-supernode-rocks',
            'appendix/serverless/supernode-case-online',
            'appendix/serverless/supernode-case-offline',
            'appendix/serverless/large-image-solution',
          ],
        },
      ],
    },
  ]
};

export default sidebars;
