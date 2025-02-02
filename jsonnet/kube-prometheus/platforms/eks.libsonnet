(import '../addons/managed-cluster.libsonnet') + {
  values+:: {
    eks: {
      minimumAvailableIPs: 10,
      minimumAvailableIPsTime: '10m',
    },
  },
  kubernetesControlPlane+: {
    serviceMonitorCoreDNS+: {
      spec+: {
        endpoints: [
          {
            bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
            interval: '15s',
            targetPort: 9153,
          },
        ],
      },
    },
    AwsEksCniMetricService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'aws-node',
        namespace: 'kube-system',
        labels: { 'app.kubernetes.io/name': 'aws-node' },
      },
      spec: {
        ports: [
          {
            name: 'cni-metrics-port',
            port: 61678,
            targetPort: 61678,
            relabelings: [
              {
                action: 'replace',
                regex: '(.*)',
                replacement: '$1',
                sourceLabels: ['__meta_kubernetes_pod_node_name'],
                targetLabel: 'instance',
              },
            ],
          },
        ],
        selector: { 'app.kubernetes.io/name': 'aws-node' },
        clusterIP: 'None',
      },
    },

    serviceMonitorAwsEksCNI: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'awsekscni',
        namespace: $.values.common.namespace,
        labels: {
          'app.kubernetes.io/name': 'eks-cni',
        },
      },
      spec: {
        jobLabel: 'app.kubernetes.io/name',
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': 'aws-node',
          },
        },
        namespaceSelector: {
          matchNames: [
            'kube-system',
          ],
        },
        endpoints: [
          {
            port: 'cni-metrics-port',
            interval: '30s',
            path: '/metrics',
          },
        ],
      },
    },
    prometheusRuleEksCNI: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PrometheusRule',
      metadata: {
        labels: $.prometheus._config.commonLabels + $.prometheus._config.mixin.ruleLabels,
        name: 'eks-rules',
        namespace: $.prometheus._config.namespace,
      },
      spec: {
        groups: [
          {
            name: 'kube-prometheus-eks.rules',
            rules: [
              {
                expr: 'sum by(instance) (awscni_ip_max) - sum by(instance) (awscni_assigned_ip_addresses) < %s' % $.values.eks.minimumAvailableIPs,
                labels: {
                  severity: 'critical',
                },
                annotations: {
                  summary: 'EKS CNI is running low on available IPs',
                  description: 'Instance {{ $labels.instance }} has only {{ $value }} IPs available which is lower than set threshold of %s' % $.values.eks.minimumAvailableIPs,
                },
                'for': $.values.eks.minimumAvailableIPsTime,
                alert: 'EksCNILowAvailableIPs',
              },
            ],
          },
        ],
      },
    },
  },
}
