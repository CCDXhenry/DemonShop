"""Offline behavioral checks: no Roblox requests or Studio edits."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
from upload_roblox_audio import upload_selected, upload_single_audio
from setup_sounds_in_studio import selected_sounds, build_setup_code
from check_roblox_audio_moderation import check_moderation, check_staged


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = self.root / 'manifest.json'
        for name in ['Click', 'Other']:
            (self.root / (name + '.mp3')).write_bytes(name.encode())
        self.uploader = Mock(return_value='123')

    def upload(self, names=('Click',), **kwargs):
        return upload_selected(list(names), self.root, self.manifest, 'group', '42', 'Test_',
                               'fake-key', uploader=self.uploader, **kwargs)

    def test_scope_reuse_change_and_history(self):
        self.assertEqual(self.upload(), [])
        self.upload()
        self.assertEqual(self.uploader.call_count, 1)
        data = json.loads(self.manifest.read_text())
        self.assertEqual(list(data['sounds']), ['Click'])
        (self.root / 'Click.mp3').write_bytes(b'changed')
        self.upload()
        self.assertEqual(self.uploader.call_count, 2)
        self.assertEqual(len(json.loads(self.manifest.read_text())['sounds']['Click']['history']), 1)

    def test_failure_preserves_mapping(self):
        self.upload()
        before = self.manifest.read_bytes()
        (self.root / 'Click.mp3').write_bytes(b'changed')
        self.uploader.side_effect = RuntimeError('mock failure')
        self.assertTrue(self.upload())
        self.assertEqual(before, self.manifest.read_bytes())

    def test_corrupt_manifest_and_missing_file_stop(self):
        self.manifest.write_text('{broken')
        with self.assertRaises(ValueError):
            self.upload()
        self.uploader.assert_not_called()
        self.manifest.unlink()
        with self.assertRaises(ValueError):
            self.upload(('Click', 'Missing'))
        self.uploader.assert_not_called()

    def test_unknown_baseline_rejected(self):
        self.manifest.write_text(json.dumps({'creator': {'groupId': '42'}, 'sounds': {'Click': {'assetId': '123'}}}))
        with self.assertRaises(ValueError):
            self.upload()
        self.uploader.assert_not_called()

    def test_deployment_hash_and_selected_scope(self):
        self.upload()
        sounds = selected_sounds(['Click'], self.root, self.manifest, 'group', '42')
        code = build_setup_code(sounds, 'group', '42', place_id=101)
        self.assertIn('assert(game.PlaceId == 101,', code)
        self.assertIn('Enum.CreatorType.Group', code)
        self.assertNotIn('Other', code)
        (self.root / 'Click.mp3').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            selected_sounds(['Click'], self.root, self.manifest, 'group', '42')

    def test_review_is_checked_once_and_unknown_is_not_approved(self):
        session = Mock()
        response = session.get.return_value
        for raw, expected in (
            ('Approved', 'approved'),
            ('MODERATION_STATE_APPROVED', 'approved'),
            ('Reviewing', 'pending'),
            ('MODERATION_STATE_REJECTED', 'rejected'),
            ('future-status', 'unknown'),
            (None, 'unknown'),
        ):
            session.reset_mock()
            response.status_code = 200
            response.json.return_value = {'moderationResult': {'moderationState': raw}}
            self.assertEqual(check_moderation(session, 'fake-key', '123')['status'], expected)
            self.assertEqual(session.get.call_count, 1)
        response.status_code = 401
        self.assertEqual(check_moderation(session, 'fake-key', '123')['httpStatus'], 401)

    def test_staged_review_is_saved_and_resume_reuses_asset_id(self):
        self.upload()
        before = self.manifest.read_bytes()
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {'moderationResult': {'moderationState': 'Pending'}}
        status = self.root / 'review.json'
        before_hash = json.loads(before)['sounds']['Click']['sha256']
        check_staged(['Click'], self.root, self.manifest, 'group', '42', 101, status, 'fake-key', session)
        saved = json.loads(status.read_text())
        self.assertEqual(saved['placeId'], 101)
        self.assertEqual(saved['sounds']['Click']['status'], 'pending')
        self.assertEqual(saved['sounds']['Click']['sha256'], before_hash)
        session.get.return_value.json.return_value = {'moderationResult': {'moderationState': 'Approved'}}
        results = check_staged(['Click'], self.root, self.manifest, 'group', '42', 101, status, 'fake-key', session)
        self.assertEqual(results['sounds']['Click']['status'], 'approved')
        self.assertEqual(self.manifest.read_bytes(), before)
        self.assertTrue(all('/123' in call.args[0] for call in session.get.call_args_list))
        self.assertEqual(self.uploader.call_count, 1)
        (self.root / 'Click.mp3').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            check_staged(['Click'], self.root, self.manifest, 'group', '42', 101, status, 'fake-key', session)
        self.assertEqual(session.get.call_count, 2)
        (self.root / 'Click.mp3').write_bytes(b'Click')
        replaced = json.loads(before)
        replaced['sounds']['Click']['assetId'] = '999'
        self.manifest.write_text(json.dumps(replaced))
        with self.assertRaises(ValueError):
            check_staged(['Click'], self.root, self.manifest, 'group', '42', 101, status, 'fake-key', session)
        self.assertEqual(session.get.call_count, 2)

    def test_operation_path_and_user_creator(self):
        session = Mock()
        session.post.return_value.status_code = 200
        session.post.return_value.json.return_value = {'path': 'operations/abc'}
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {'done': True, 'response': {'assetId': '321'}}
        result = upload_single_audio(session, 'fake', 'Click', self.root / 'Click.mp3', 'user', '7', 'Test_')
        self.assertEqual(result, '321')
        self.assertEqual(session.get.call_args.args[0], 'https://apis.roblox.com/assets/v1/operations/abc')
        payload = json.loads(session.post.call_args.kwargs['files']['request'][1])
        self.assertEqual(payload['creationContext']['creator'], {'userId': '7'})


if __name__ == '__main__':
    unittest.main()
