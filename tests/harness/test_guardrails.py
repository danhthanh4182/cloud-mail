import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('harness',Path(__file__).resolve().parents[2]/'scripts/harness.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

class GuardrailTests(unittest.TestCase):
    def setUp(self):
        self.config={'forbidden_tracked_extensions':['.apk','.aab','.jks','.keystore'],'forbidden_directory_segments':['build','node_modules']}

    def test_builds_and_keys_rejected_but_source_assets_allowed(self):
        errors=harness.path_errors(['app/build/demo.apk','signing/key.jks','design/logo.svg','app/lib/main.dart'],self.config)
        self.assertTrue(any('demo.apk' in e for e in errors))
        self.assertTrue(any('key.jks' in e for e in errors))
        self.assertFalse(any('logo.svg' in e or 'main.dart' in e for e in errors))

    def test_orchestration_rejects_cycles_and_missing_dependencies(self):
        tasks=[{'id':'A','role':'dev','depends_on':['B']},{'id':'B','role':'dev','depends_on':['A','missing']}]
        errors=harness.dag_errors(tasks,{'dev':'engineer'})
        self.assertTrue(any('cycle' in e for e in errors))
        self.assertTrue(any('Unknown dependency' in e for e in errors))

    def test_valid_dag_passes(self):
        self.assertEqual([],harness.dag_errors([{'id':'A','role':'dev','depends_on':[]},{'id':'B','role':'dev','depends_on':['A']}],{'dev':'engineer'}))

    def test_release_rejects_stale_or_missing_evidence(self):
        errors=harness.release_errors({'status':'pending'},{'source_revision':'old','checks':[]},'new',['unit','device'])
        self.assertEqual(4,len(errors))

    def test_release_requires_decision_and_each_check_reference(self):
        approval={'status':'approved','decision_reference':'recorded-user-decision'}
        evidence={'source_revision':'source','checks':[{'name':'unit','result':'passed','evidence_reference':'ci/run/test-report'}]}
        self.assertEqual([],harness.release_errors(approval,evidence,'source',['unit']))
        evidence['checks'][0].pop('evidence_reference')
        self.assertTrue(harness.release_errors(approval,evidence,'source',['unit']))

if __name__ == '__main__': unittest.main()
