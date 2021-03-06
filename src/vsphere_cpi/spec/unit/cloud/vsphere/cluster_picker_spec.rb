require 'spec_helper'

module VSphereCloud
  describe ClusterPicker do
    describe '#best_cluster_placement' do
      context 'when one cluster fits' do
        let(:available_clusters) { [cluster_1] }
        let(:cluster_1) do
          instance_double(VSphereCloud::Resources::Cluster,
            name: 'cluster-1',
            free_memory: 2048,
            accessible_datastores: {
              'target-ds' => target_ds,
            }
          )
        end
        let(:target_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 512) }

        it 'returns the first placement option' do
          disks = [
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              target_datastore_pattern: 'target-ds',
              existing_datastore_name: nil
            ),
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              ephemeral?: true,
              target_datastore_pattern: 'target-ds',
              existing_datastore_name: nil
            ),
          ]

          picker = ClusterPicker.new(0, 0)
          picker.update(available_clusters)

          placement_option = picker.best_cluster_placement(req_memory: 1024, disk_configurations: disks)
          expect(placement_option).to eq({
            'cluster-1' => {
              disks[0] => 'target-ds',
              disks[1] => 'target-ds',
            }
          })
        end
      end

      context 'when no cluster fits' do
        let(:available_clusters) { [cluster_1] }
        let(:cluster_1) do
          instance_double(VSphereCloud::Resources::Cluster,
            name: 'cluster-1',
            free_memory: 2048,
            accessible_datastores: {
              'not-matching-ds' => not_matching_ds,
            }
          )
        end
        let(:not_matching_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }

        context 'based upon available memory' do
          it 'raises a CloudError when mem_headroom is provided' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 0,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            expect {
              picker.best_cluster_placement(req_memory: 4096, disk_configurations: disks)
            }.to raise_error(Bosh::Clouds::CloudError, /No valid placement found for requested memory/)
          end

          it 'raises a CloudError when mem_headroom is default' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 0,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new
            picker.update(available_clusters)

            expect {
              picker.best_cluster_placement(req_memory: 2048 - ClusterPicker::DEFAULT_MEMORY_HEADROOM + 1, disk_configurations: disks)
            }.to raise_error(Bosh::Clouds::CloudError, /No valid placement found for requested memory/)
          end
        end

        context 'based upon available free space' do
          it 'raises a CloudError when disk_headroom is provided' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 2048,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            expect {
              picker.best_cluster_placement(req_memory: 0, disk_configurations: disks)
            }.to raise_error(Bosh::Clouds::CloudError, /No valid placement found for disks/)
          end

          it 'raises a CloudError when disk_headroom is default' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 1024 - DatastorePicker::DEFAULT_DISK_HEADROOM + 1,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new
            picker.update(available_clusters)

            expect {
              picker.best_cluster_placement(req_memory: 0, disk_configurations: disks)
            }.to raise_error(Bosh::Clouds::CloudError, /No valid placement found for disks/)
          end
        end

        context 'based upon target datastore pattern' do
          it 'raises a CloudError' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 0,
                target_datastore_pattern: 'target-ds',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            expect {
              picker.best_cluster_placement(req_memory: 0, disk_configurations: disks)
            }.to raise_error(Bosh::Clouds::CloudError, /No valid placement found for disks/)
          end
        end
      end

      context 'when multiple clusters fit' do
        context 'when disk migration burden provides a decision' do
          let(:available_clusters) { [cluster_1, cluster_2] }
          let(:cluster_1) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-1',
              free_memory: 2048,
              accessible_datastores: {
                'other-ds' => other_ds,
              }
            )
          end
          let(:cluster_2) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-2',
              free_memory: 2048,
              accessible_datastores: {
                'current-ds' => current_ds,
              }
            )
          end
          let(:other_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 512) }
          let(:current_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 512) }

          it 'returns the cluster' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 256,
                target_datastore_pattern: '.*',
                existing_datastore_name: 'current-ds',
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            placement_option = picker.best_cluster_placement(req_memory: 1024, disk_configurations: disks)
            expect(placement_option).to eq({
              'cluster-2' => {
                disks[0] => 'current-ds',
              }
            })
          end
        end

        context 'when max free space provides a decision' do
          let(:available_clusters) { [cluster_1, cluster_2] }
          let(:cluster_1) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-1',
              free_memory: 2048,
              accessible_datastores: {
                'smaller-ds' => smaller_ds,
              }
            )
          end
          let(:cluster_2) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-2',
              free_memory: 2048,
              accessible_datastores: {
                'larger-ds' => larger_ds,
              }
            )
          end
          let(:smaller_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 512) }
          let(:larger_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }

          it 'returns the cluster' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 256,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            placement_option = picker.best_cluster_placement(req_memory: 1024, disk_configurations: disks)
            expect(placement_option).to eq({
              'cluster-2' => {
                disks[0] => 'larger-ds',
              }
            })
          end
        end

        context 'when max free memory provides a decision' do
          let(:available_clusters) { [cluster_1, cluster_2] }
          let(:cluster_1) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-1',
              free_memory: 4096,
              accessible_datastores: {
                'same-ds' => same_ds,
              }
            )
          end
          let(:cluster_2) do
            instance_double(VSphereCloud::Resources::Cluster,
              name: 'cluster-2',
              free_memory: 2048,
              accessible_datastores: {
                'same-ds' => same_ds,
              }
            )
          end
          let(:same_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }

          it 'returns the cluster' do
            disks = [
              instance_double(VSphereCloud::DiskConfig,
                size: 256,
                target_datastore_pattern: '.*',
                existing_datastore_name: nil
              )
            ]

            picker = ClusterPicker.new(0, 0)
            picker.update(available_clusters)

            placement_option = picker.best_cluster_placement(req_memory: 1024, disk_configurations: disks)
            expect(placement_option).to eq({
              'cluster-1' => {
                disks[0] => 'same-ds',
              }
            })
          end
        end
      end
    end
  end
end
