import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tkeSidebar: [
    'README',
    {
      type: 'category',
      label: '网络指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/networking'
      },
      items: [
        {
          type: 'category',
          label: '在 TKE 自建 Nginx Ingress Controller',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/networking/ingress-nginx'
          },
          items: [
            'networking/ingress-nginx/quick-start',
            'networking/ingress-nginx/clb',
            'networking/ingress-nginx/clb-direct-access',
            'networking/ingress-nginx/high-concurrency',
            'networking/ingress-nginx/high-availability',
            'networking/ingress-nginx/observability',
            'networking/ingress-nginx/waf',
            'networking/ingress-nginx/multi-ingress-controller',
            'networking/ingress-nginx/migrate',
            'networking/ingress-nginx/values-demo',
          ],
        },
        'networking/traffic-lossless-upgrade',
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
      label: '弹性伸缩',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/autoscaling'
      },
      items: [
        {
          type: 'category',
          label: '事件驱动弹性伸缩最佳实践(KEDA)',
          collapsed: true,
          link: {
            type: 'generated-index',
            slug: '/autoscaling/keda'
          },
          items: [
            'autoscaling/keda/overview',
            'autoscaling/keda/install',
            'autoscaling/keda/cron',
            'autoscaling/keda/workload',
            'autoscaling/keda/clb',
            'autoscaling/keda/pulsar',
            'autoscaling/keda/cnapigw',
          ]
        },
        'autoscaling/tke-autoscaling-placeholder',
      ],
    },
    {
      type: 'category',
      label: 'OPA 策略管理',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/opa'
      },
      items: [
        'opa/install',
        'opa/block-public-ingress',
      ],
    },
    {
      type: 'category',
      label: '可观测性指南',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/observability'
      },
      items: [
        'observability/prometheus-scrape-config',
        'observability/grafana-dashboard-for-supernode-pod',
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
      label: '应用管理',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/apps'
      },
      items: [
        'apps/upgrade-inplace'
      ]
    },
    {
      type: 'category',
      label: '常见应用部署',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/deploy'
      },
      items: [
        'deploy/harbor',
        'deploy/gitlab',
        'deploy/kubesphere',
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
        'appendix/kubectl',
        'appendix/ingress-error-code',
        'appendix/eks-note',
      ],
    },
  ]
};

export default sidebars;
